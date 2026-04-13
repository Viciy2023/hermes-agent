import asyncio
from pathlib import Path

from huggingface.runtime_state import plan_bidirectional_sync, should_run_weixin_qr_login


def _write(path: Path, content: str, mtime_ns: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    import os

    os.utime(path, ns=(mtime_ns, mtime_ns))


def test_plan_bidirectional_sync_only_copies_changed_files(tmp_path):
    runtime = tmp_path / "runtime"
    persist = tmp_path / "persist"

    _write(runtime / "same.txt", "same", 2_000_000_000)
    _write(persist / "same.txt", "same", 2_000_000_000)

    _write(runtime / "runtime-newer.txt", "runtime", 3_000_000_000)
    _write(persist / "runtime-newer.txt", "persist", 2_000_000_000)

    _write(runtime / "runtime-only.txt", "runtime-only", 3_000_000_000)
    _write(persist / "persist-only.txt", "persist-only", 3_000_000_000)

    actions = plan_bidirectional_sync(runtime, persist)

    assert ("runtime_to_persist", "runtime-newer.txt") in actions
    assert ("runtime_to_persist", "runtime-only.txt") in actions
    assert ("persist_to_runtime", "persist-only.txt") in actions
    assert all(rel_path != "same.txt" for _, rel_path in actions)


def test_plan_bidirectional_sync_ignores_transient_files(tmp_path):
    runtime = tmp_path / "runtime"
    persist = tmp_path / "persist"

    _write(runtime / "weixin" / "accounts" / "acct.context-tokens.json", "token", 3_000_000_000)
    _write(runtime / "cron" / ".tick.lock", "lock", 3_000_000_000)
    _write(runtime / "keep.txt", "keep", 3_000_000_000)

    actions = plan_bidirectional_sync(runtime, persist)

    assert actions == [("runtime_to_persist", "keep.txt")]


def test_should_run_weixin_qr_login_reuses_saved_credentials_without_prevalidation():
    env = {
        "WEIXIN_ENABLED": "true",
        "WEIXIN_ACCOUNT_ID": "acct",
        "WEIXIN_TOKEN": "token",
        "WEIXIN_BASE_URL": "https://ilink.example.com",
    }

    should_run, reason = asyncio.run(should_run_weixin_qr_login(env))

    assert should_run is False
    assert reason == "credentials_present"


def test_should_run_weixin_qr_login_still_requests_qr_when_credentials_are_missing():
    env = {
        "WEIXIN_ENABLED": "true",
    }

    should_run, reason = asyncio.run(should_run_weixin_qr_login(env))

    assert should_run is True
    assert reason == "missing_credentials"
