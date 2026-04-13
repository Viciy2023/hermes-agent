from __future__ import annotations

import hashlib
import shutil
from pathlib import Path
from typing import Iterable, Mapping

TRANSIENT_SUFFIXES = (
    ".sync.json",
    ".context-tokens.json",
    ".tick.lock",
    ".pyc",
    ".pyo",
    ".tmp",
    ".temp",
)

TRANSIENT_PARTS = {
    "__pycache__",
}


def _is_truthy(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = str(value).strip().lower()
    if not normalized:
        return default
    return normalized in {"1", "true", "yes", "on"}


def _should_skip(rel_path: str) -> bool:
    parts = Path(rel_path).parts
    if any(part in TRANSIENT_PARTS for part in parts):
        return True
    return rel_path.endswith(TRANSIENT_SUFFIXES)


def _file_signature(path: Path) -> tuple[int, int]:
    stat = path.stat()
    return stat.st_mtime_ns, stat.st_size


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _iter_files(root: Path) -> Iterable[str]:
    if not root.exists():
        return []

    rel_paths: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel_path = path.relative_to(root).as_posix()
        if _should_skip(rel_path):
            continue
        rel_paths.append(rel_path)
    return sorted(rel_paths)


def plan_bidirectional_sync(runtime_root: Path, persist_root: Path) -> list[tuple[str, str]]:
    runtime_files = {rel_path: runtime_root / rel_path for rel_path in _iter_files(runtime_root)}
    persist_files = {rel_path: persist_root / rel_path for rel_path in _iter_files(persist_root)}
    actions: list[tuple[str, str]] = []

    for rel_path in sorted(set(runtime_files) | set(persist_files)):
        runtime_path = runtime_files.get(rel_path)
        persist_path = persist_files.get(rel_path)

        if runtime_path and not persist_path:
            actions.append(("runtime_to_persist", rel_path))
            continue
        if persist_path and not runtime_path:
            actions.append(("persist_to_runtime", rel_path))
            continue
        if not runtime_path or not persist_path:
            continue

        runtime_sig = _file_signature(runtime_path)
        persist_sig = _file_signature(persist_path)
        if runtime_sig == persist_sig and _hash_file(runtime_path) == _hash_file(persist_path):
            continue

        if runtime_sig[0] > persist_sig[0]:
            actions.append(("runtime_to_persist", rel_path))
            continue
        if persist_sig[0] > runtime_sig[0]:
            actions.append(("persist_to_runtime", rel_path))
            continue

        if _hash_file(runtime_path) != _hash_file(persist_path):
            actions.append(("runtime_to_persist", rel_path))

    return actions


def apply_sync_actions(runtime_root: Path, persist_root: Path, actions: Iterable[tuple[str, str]]) -> None:
    for direction, rel_path in actions:
        if direction == "runtime_to_persist":
            src = runtime_root / rel_path
            dest = persist_root / rel_path
        else:
            src = persist_root / rel_path
            dest = runtime_root / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)


async def should_run_weixin_qr_login(
    env: Mapping[str, str | None],
) -> tuple[bool, str]:
    intent_keys = [
        "WEIXIN_DM_POLICY",
        "WEIXIN_GROUP_POLICY",
        "WEIXIN_ALLOWED_USERS",
        "WEIXIN_GROUP_ALLOWED_USERS",
        "WEIXIN_HOME_CHANNEL",
        "WEIXIN_HOME_CHANNEL_NAME",
        "WEIXIN_BASE_URL",
        "WEIXIN_CDN_BASE_URL",
        "WEIXIN_ALLOW_ALL_USERS",
    ]

    weixin_requested = _is_truthy(env.get("WEIXIN_ENABLED"), False) or any(env.get(key) for key in intent_keys)
    if not weixin_requested:
        return False, "not_requested"

    auto_qr_enabled = _is_truthy(env.get("WEIXIN_AUTO_QR_LOGIN"), True)
    account_id = str(env.get("WEIXIN_ACCOUNT_ID") or "").strip()
    token = str(env.get("WEIXIN_TOKEN") or "").strip()

    if account_id and token:
        return False, "credentials_present"

    if not auto_qr_enabled:
        return False, "missing_credentials_auto_qr_disabled"
    return True, "missing_credentials"
