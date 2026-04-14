#!/bin/bash
set -e

PERSIST_HOME_RAW="${HERMES_HOME:-/data}"
PERSIST_HOME="$(printf '%s' "$PERSIST_HOME_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
RUNTIME_HOME_RAW="${HERMES_RUNTIME_HOME:-/tmp/hermes-runtime}"
RUNTIME_HOME="$(printf '%s' "$RUNTIME_HOME_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
PERSIST_SYNC_SECONDS="${HERMES_PERSIST_SYNC_SECONDS:-300}"
INSTALL_DIR="/opt/hermes"

SYNC_CONFIG_BATCH=(
    ".env"
    "config.yaml"
    "SOUL.md"
    "state.db"
    "weixin/accounts"
    "channel_directory.json"
    "auth.json"
    "processes.json"
    "gateway_voice_mode.json"
)
SYNC_DIR_BATCHES=(
    "sessions"
    "memories"
    "plans"
    "cron"
    "workspace"
    "home"
    "hooks"
    "skills"
    "skins"
    "optional-skills"
    "plugins"
    "scripts"
)

should_exclude_path() {
    local rel_path="$1"
    case "$rel_path" in
        *__pycache__/*|*.pyc|*.tmp|*.temp|*.lock)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

copy_file_to_target() {
    local src_root="$1"
    local dest_root="$2"
    local rel_path="$3"
    local src="$src_root/$rel_path"
    local dest="$dest_root/$rel_path"

    if [ ! -f "$src" ]; then
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    cp -f "$src" "$dest" 2>/dev/null || true
}

copy_tree_to_target() {
    local src_root="$1"
    local dest_root="$2"
    local rel_dir="$3"
    local src_dir="$src_root/$rel_dir"

    if [ ! -d "$src_dir" ]; then
        return 0
    fi

    while IFS= read -r -d '' src_path; do
        local rel_path="${src_path#${src_root}/}"
        if should_exclude_path "$rel_path"; then
            continue
        fi
        local dest_path="$dest_root/$rel_path"
        mkdir -p "$(dirname "$dest_path")"
        cp -f "$src_path" "$dest_path" 2>/dev/null || true
    done < <(find "$src_dir" -type f -print0)
}

restore_runtime_from_persist() {
    local item

    for item in "${SYNC_CONFIG_BATCH[@]}"; do
        if [ -d "$PERSIST_HOME/$item" ]; then
            copy_tree_to_target "$PERSIST_HOME" "$RUNTIME_HOME" "$item"
        else
            copy_file_to_target "$PERSIST_HOME" "$RUNTIME_HOME" "$item"
        fi
    done

    for item in "${SYNC_DIR_BATCHES[@]}"; do
        copy_tree_to_target "$PERSIST_HOME" "$RUNTIME_HOME" "$item"
    done
}

sync_batch_to_persist() {
    local batch_name="$1"
    local item

    if [ "$batch_name" = "config" ]; then
        for item in "${SYNC_CONFIG_BATCH[@]}"; do
            if [ -d "$RUNTIME_HOME/$item" ]; then
                copy_tree_to_target "$RUNTIME_HOME" "$PERSIST_HOME" "$item"
            else
                copy_file_to_target "$RUNTIME_HOME" "$PERSIST_HOME" "$item"
            fi
        done
        return 0
    fi

    copy_tree_to_target "$RUNTIME_HOME" "$PERSIST_HOME" "$batch_name"
}

sync_all_batches_to_persist() {
    local item

    sync_batch_to_persist "config"
    for item in "${SYNC_DIR_BATCHES[@]}"; do
        sync_batch_to_persist "$item"
    done
}

start_persist_sync_loop() {
    local batch_index=0
    local total_batches=$((1 + ${#SYNC_DIR_BATCHES[@]}))

    while true; do
        sleep "$PERSIST_SYNC_SECONDS"
        if [ "$batch_index" -eq 0 ]; then
            sync_batch_to_persist "config"
        else
            sync_batch_to_persist "${SYNC_DIR_BATCHES[$((batch_index - 1))]}"
        fi
        batch_index=$(((batch_index + 1) % total_batches))
    done
}

mkdir -p "$PERSIST_HOME" "$RUNTIME_HOME"

ACTIVATE_PATH=""
if [ -f "${INSTALL_DIR}/.venv/bin/activate" ]; then
    ACTIVATE_PATH="${INSTALL_DIR}/.venv/bin/activate"
fi
if [ -z "$ACTIVATE_PATH" ] && [ -f "${INSTALL_DIR}/venv/bin/activate" ]; then
    ACTIVATE_PATH="${INSTALL_DIR}/venv/bin/activate"
fi
if [ -n "$ACTIVATE_PATH" ]; then
    source "$ACTIVATE_PATH"
fi

export HERMES_PERSIST_HOME="$PERSIST_HOME"
export HERMES_HOME="$RUNTIME_HOME"
export PERSIST_HOME RUNTIME_HOME INSTALL_DIR

mkdir -p "$PERSIST_HOME" "$RUNTIME_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home,optional-skills,weixin/accounts,plugins,scripts}

if [ ! -f "$PERSIST_HOME/.env" ]; then
    cp "$INSTALL_DIR/huggingface/.env.space.example" "$PERSIST_HOME/.env"
fi

if [ ! -f "$PERSIST_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/huggingface/config.space.yaml" "$PERSIST_HOME/config.yaml"
fi

if [ ! -f "$PERSIST_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$PERSIST_HOME/SOUL.md"
fi

restore_runtime_from_persist

if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

export HERMES_HOME="$PERSIST_HOME"
python3 - <<'PY'
import asyncio
import json
import os
import sys
from pathlib import Path

from gateway.platforms.weixin import check_weixin_requirements, qr_login
from hermes_cli.config import get_env_value, save_env_value


def truthy(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = str(value).strip().lower()
    if not normalized:
        return default
    return normalized in {"1", "true", "yes", "on"}


def should_run_weixin_qr_login(env: dict[str, str | None]) -> tuple[bool, str]:
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

    weixin_requested = truthy(env.get("WEIXIN_ENABLED"), False) or any(env.get(key) for key in intent_keys)
    if not weixin_requested:
        return False, "not_requested"

    auto_qr_enabled = truthy(env.get("WEIXIN_AUTO_QR_LOGIN"), True)
    account_id = str(env.get("WEIXIN_ACCOUNT_ID") or "").strip()
    token = str(env.get("WEIXIN_TOKEN") or "").strip()

    if account_id and token:
        return False, "credentials_present"

    if not auto_qr_enabled:
        return False, "missing_credentials_auto_qr_disabled"
    return True, "missing_credentials"


def load_weixin_account_fallback(hermes_home: str, account_id_hint: str) -> dict[str, str]:
    accounts_dir = Path(hermes_home) / "weixin" / "accounts"
    if not accounts_dir.exists():
        return {}

    candidates = []
    if account_id_hint:
        candidates.append(accounts_dir / f"{account_id_hint}.json")
    candidates.extend(sorted(accounts_dir.glob("*.json"), reverse=True))

    seen = set()
    for candidate in candidates:
        candidate = candidate.resolve()
        if candidate in seen or not candidate.is_file():
            continue
        seen.add(candidate)
        try:
            data = json.loads(candidate.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"Weixin bootstrap: failed to read persisted account file {candidate}: {exc}")
            continue
        token = str(data.get("token") or "").strip()
        base_url = str(data.get("base_url") or "").strip()
        account_id = candidate.stem
        if token:
            return {
                "WEIXIN_ACCOUNT_ID": account_id,
                "WEIXIN_TOKEN": token,
                "WEIXIN_BASE_URL": base_url,
                "_source": str(candidate),
            }
    return {}


hermes_home = os.getenv("HERMES_HOME", "/data")
env_values = {
    key: get_env_value(key) or os.getenv(key)
    for key in [
        "WEIXIN_ENABLED",
        "WEIXIN_AUTO_QR_LOGIN",
        "WEIXIN_ACCOUNT_ID",
        "WEIXIN_TOKEN",
        "WEIXIN_BASE_URL",
        "WEIXIN_CDN_BASE_URL",
        "WEIXIN_DM_POLICY",
        "WEIXIN_GROUP_POLICY",
        "WEIXIN_ALLOWED_USERS",
        "WEIXIN_GROUP_ALLOWED_USERS",
        "WEIXIN_HOME_CHANNEL",
        "WEIXIN_HOME_CHANNEL_NAME",
        "WEIXIN_ALLOW_ALL_USERS",
    ]
}

print(
    "Weixin bootstrap: env snapshot "
    f"account_id={'set' if env_values.get('WEIXIN_ACCOUNT_ID') else 'missing'} "
    f"token={'set' if env_values.get('WEIXIN_TOKEN') else 'missing'} "
    f"base_url={env_values.get('WEIXIN_BASE_URL') or '(missing)'}"
)

if not env_values.get("WEIXIN_ACCOUNT_ID") or not env_values.get("WEIXIN_TOKEN"):
    fallback = load_weixin_account_fallback(hermes_home, str(env_values.get("WEIXIN_ACCOUNT_ID") or "").strip())
    if fallback:
        print(
            "Weixin bootstrap: loaded persisted account file "
            f"source={fallback.get('_source')} account_id={fallback.get('WEIXIN_ACCOUNT_ID')}"
        )
        env_values["WEIXIN_ACCOUNT_ID"] = fallback.get("WEIXIN_ACCOUNT_ID")
        env_values["WEIXIN_TOKEN"] = fallback.get("WEIXIN_TOKEN")
        if fallback.get("WEIXIN_BASE_URL"):
            env_values["WEIXIN_BASE_URL"] = fallback.get("WEIXIN_BASE_URL")

print(
    "Weixin bootstrap: effective credentials "
    f"account_id={'set' if env_values.get('WEIXIN_ACCOUNT_ID') else 'missing'} "
    f"token={'set' if env_values.get('WEIXIN_TOKEN') else 'missing'} "
    f"base_url={env_values.get('WEIXIN_BASE_URL') or '(missing)'}"
)

should_run_qr, reason = should_run_weixin_qr_login(env_values)

if reason == "not_requested":
    sys.exit(0)

if not should_run_qr and reason == "credentials_present":
    print("Weixin bootstrap: credentials present, reusing saved session.")
    sys.exit(0)

if not should_run_qr:
    if reason == "missing_credentials_auto_qr_disabled":
        print("Weixin bootstrap: WEIXIN_AUTO_QR_LOGIN is disabled and credentials are missing.")
    else:
        print(f"Weixin bootstrap skipped: {reason}")
    sys.exit(1)

if not check_weixin_requirements():
    print("Weixin bootstrap failed: aiohttp and cryptography are required.")
    sys.exit(1)

try:
    timeout_seconds = int(os.getenv("WEIXIN_QR_TIMEOUT_SECONDS", "480"))
except ValueError:
    timeout_seconds = 480

print("Weixin bootstrap: credentials missing, starting QR login in container logs...")
result = asyncio.run(qr_login(hermes_home, timeout_seconds=timeout_seconds))
if not result:
    print("Weixin bootstrap failed or timed out. Restart the Space to generate a new QR code.")
    sys.exit(1)

save_env_value("WEIXIN_ACCOUNT_ID", result.get("account_id", ""))
save_env_value("WEIXIN_TOKEN", result.get("token", ""))
base_url = result.get("base_url", "")
if base_url:
    save_env_value("WEIXIN_BASE_URL", base_url)
if not get_env_value("WEIXIN_CDN_BASE_URL"):
    save_env_value("WEIXIN_CDN_BASE_URL", "https://novac2c.cdn.weixin.qq.com/c2c")

user_id = result.get("user_id", "")
if truthy(os.getenv("WEIXIN_AUTO_SET_HOME_CHANNEL"), True) and user_id and not get_env_value("WEIXIN_HOME_CHANNEL"):
    save_env_value("WEIXIN_HOME_CHANNEL", user_id)
    save_env_value("WEIXIN_HOME_CHANNEL_NAME", get_env_value("WEIXIN_HOME_CHANNEL_NAME") or "Home")

print(f"Weixin bootstrap succeeded: credentials were saved to {hermes_home}/.env.")
PY

python3 - <<'PY'
import os
import shutil
from pathlib import Path

persist_env = Path(os.environ["PERSIST_HOME"]) / ".env"
runtime_env = Path(os.environ["RUNTIME_HOME"]) / ".env"
if persist_env.exists():
    runtime_env.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(persist_env, runtime_env)
PY

ACTIVE_CUSTOM_MODEL="${ACTIVE_CUSTOM_MODEL:-primary}"
PRIMARY_CUSTOM_ENDPOINT_URL="${CUSTOM_OPENAI_BASE_URL:-${OPENAI_BASE_URL:-}}"
SECONDARY_CUSTOM_ENDPOINT_URL="${SECONDARY_CUSTOM_OPENAI_BASE_URL:-${SECONDARY_OPENAI_BASE_URL:-}}"
SELECTED_CUSTOM_ENDPOINT_URL="$PRIMARY_CUSTOM_ENDPOINT_URL"
SELECTED_MODEL_NAME="${HERMES_MODEL:-}"

export HERMES_HOME="$PERSIST_HOME"

if [ "$ACTIVE_CUSTOM_MODEL" = "secondary" ]; then
    SELECTED_CUSTOM_ENDPOINT_URL="$SECONDARY_CUSTOM_ENDPOINT_URL"
    SELECTED_MODEL_NAME="${SECONDARY_HERMES_MODEL:-}"
    if [ -z "$SELECTED_CUSTOM_ENDPOINT_URL" ]; then
        echo "ACTIVE_CUSTOM_MODEL=secondary but SECONDARY_CUSTOM_OPENAI_BASE_URL/SECONDARY_OPENAI_BASE_URL is not set"
        exit 1
    fi
    if [ -z "$SELECTED_MODEL_NAME" ]; then
        echo "ACTIVE_CUSTOM_MODEL=secondary but SECONDARY_HERMES_MODEL is not set"
        exit 1
    fi
fi

if [ -n "$SELECTED_CUSTOM_ENDPOINT_URL" ]; then
    hermes config set model.provider "custom"
    hermes config set model.base_url "$SELECTED_CUSTOM_ENDPOINT_URL"
fi
if [ -z "$SELECTED_CUSTOM_ENDPOINT_URL" ] && [ -n "${HERMES_INFERENCE_PROVIDER:-}" ]; then
    hermes config set model.provider "$HERMES_INFERENCE_PROVIDER"
fi

if [ -n "$SELECTED_MODEL_NAME" ]; then
    hermes config set model.default "$SELECTED_MODEL_NAME"
fi

if [ "$ACTIVE_CUSTOM_MODEL" = "secondary" ]; then
    if [ -z "${OPENAI_API_KEY:-}" ]; then
        if [ -n "${SECONDARY_OPENAI_API_KEY:-}" ]; then
            export OPENAI_API_KEY="$SECONDARY_OPENAI_API_KEY"
        fi
        if [ -z "${OPENAI_API_KEY:-}" ] && [ -n "${SECONDARY_ANTHROPIC_APILKEY:-}" ]; then
            export OPENAI_API_KEY="$SECONDARY_ANTHROPIC_APILKEY"
        fi
        if [ -z "${OPENAI_API_KEY:-}" ] && [ -n "${SECONDARY_ANTHROPIC_API_KEY:-}" ]; then
            export OPENAI_API_KEY="$SECONDARY_ANTHROPIC_API_KEY"
        fi
        if [ -z "${OPENAI_API_KEY:-}" ] && [ -n "${ANTHROPIC_APILKEY:-}" ]; then
            export OPENAI_API_KEY="$ANTHROPIC_APILKEY"
        fi
        if [ -z "${OPENAI_API_KEY:-}" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            export OPENAI_API_KEY="$ANTHROPIC_API_KEY"
        fi
    fi
else
    if [ -z "${OPENAI_API_KEY:-}" ]; then
        if [ -n "${ANTHROPIC_APILKEY:-}" ]; then
            export OPENAI_API_KEY="$ANTHROPIC_APILKEY"
        fi
        if [ -z "${OPENAI_API_KEY:-}" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            export OPENAI_API_KEY="$ANTHROPIC_API_KEY"
        fi
    fi
fi

export API_SERVER_ENABLED="${API_SERVER_ENABLED:-true}"
export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"
export API_SERVER_PORT="${API_SERVER_PORT:-${PORT:-7860}}"
export API_SERVER_MODEL_NAME="${API_SERVER_MODEL_NAME:-Hermes-Agent}"

sync_all_batches_to_persist

export HERMES_HOME="$RUNTIME_HOME"

start_persist_sync_loop &
SYNC_PID=$!

hermes gateway run &
MAIN_PID=$!

STATUS=0
if ! wait "$MAIN_PID"; then
    STATUS=$?
fi

kill "$SYNC_PID" 2>/dev/null || true
sync_all_batches_to_persist || true

exit "$STATUS"
