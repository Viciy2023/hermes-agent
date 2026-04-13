#!/bin/bash
set -e
shopt -s nullglob

PERSIST_HOME_RAW="${HERMES_HOME:-/data}"
PERSIST_HOME="$(printf '%s' "$PERSIST_HOME_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
RUNTIME_HOME_RAW="${HERMES_RUNTIME_HOME:-/tmp/hermes-runtime}"
RUNTIME_HOME="$(printf '%s' "$RUNTIME_HOME_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
PERSIST_SYNC_SECONDS="${HERMES_PERSIST_SYNC_SECONDS:-120}"
INSTALL_DIR="/opt/hermes"

sync_file_if_present() {
    local src="$1"
    local dest="$2"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -f "$src" "$dest"
    fi
}

sync_dir_contents() {
    local src="$1"
    local dest="$2"
    if [ -d "$src" ]; then
        mkdir -p "$dest"
        cp -a "$src"/. "$dest"/
    fi
}

sync_weixin_persist_to_runtime() {
    local persist_accounts="$PERSIST_HOME/weixin/accounts"
    local runtime_accounts="$RUNTIME_HOME/weixin/accounts"
    mkdir -p "$runtime_accounts"
    for file in "$persist_accounts"/*.json; do
        [ -f "$file" ] || continue
        cp -f "$file" "$runtime_accounts/$(basename "$file")"
    done
}

sync_weixin_runtime_to_persist() {
    local persist_accounts="$PERSIST_HOME/weixin/accounts"
    local runtime_accounts="$RUNTIME_HOME/weixin/accounts"
    mkdir -p "$persist_accounts"
    for file in "$runtime_accounts"/*.json; do
        [ -f "$file" ] || continue
        case "$(basename "$file")" in
            *.sync.json|*.context-tokens.json)
                continue
                ;;
        esac
        cp -f "$file" "$persist_accounts/$(basename "$file")"
    done
}

sync_persist_to_runtime() {
    sync_file_if_present "$PERSIST_HOME/.env" "$RUNTIME_HOME/.env"
    sync_file_if_present "$PERSIST_HOME/config.yaml" "$RUNTIME_HOME/config.yaml"
    sync_file_if_present "$PERSIST_HOME/SOUL.md" "$RUNTIME_HOME/SOUL.md"
    sync_file_if_present "$PERSIST_HOME/state.db" "$RUNTIME_HOME/state.db"
    sync_dir_contents "$PERSIST_HOME/sessions" "$RUNTIME_HOME/sessions"
    sync_dir_contents "$PERSIST_HOME/memories" "$RUNTIME_HOME/memories"
    sync_dir_contents "$PERSIST_HOME/skills" "$RUNTIME_HOME/skills"
    sync_dir_contents "$PERSIST_HOME/cron" "$RUNTIME_HOME/cron"
    sync_dir_contents "$PERSIST_HOME/home" "$RUNTIME_HOME/home"
    sync_dir_contents "$PERSIST_HOME/hooks" "$RUNTIME_HOME/hooks"
    sync_dir_contents "$PERSIST_HOME/skins" "$RUNTIME_HOME/skins"
    sync_dir_contents "$PERSIST_HOME/plans" "$RUNTIME_HOME/plans"
    sync_dir_contents "$PERSIST_HOME/workspace" "$RUNTIME_HOME/workspace"
    sync_weixin_persist_to_runtime
}

sync_runtime_to_persist() {
    sync_file_if_present "$RUNTIME_HOME/.env" "$PERSIST_HOME/.env"
    sync_file_if_present "$RUNTIME_HOME/config.yaml" "$PERSIST_HOME/config.yaml"
    sync_file_if_present "$RUNTIME_HOME/SOUL.md" "$PERSIST_HOME/SOUL.md"
    sync_file_if_present "$RUNTIME_HOME/state.db" "$PERSIST_HOME/state.db"
    sync_dir_contents "$RUNTIME_HOME/sessions" "$PERSIST_HOME/sessions"
    sync_dir_contents "$RUNTIME_HOME/memories" "$PERSIST_HOME/memories"
    sync_dir_contents "$RUNTIME_HOME/skills" "$PERSIST_HOME/skills"
    sync_dir_contents "$RUNTIME_HOME/cron" "$PERSIST_HOME/cron"
    sync_dir_contents "$RUNTIME_HOME/home" "$PERSIST_HOME/home"
    sync_dir_contents "$RUNTIME_HOME/hooks" "$PERSIST_HOME/hooks"
    sync_dir_contents "$RUNTIME_HOME/skins" "$PERSIST_HOME/skins"
    sync_dir_contents "$RUNTIME_HOME/plans" "$PERSIST_HOME/plans"
    sync_dir_contents "$RUNTIME_HOME/workspace" "$PERSIST_HOME/workspace"
    sync_weixin_runtime_to_persist
}

start_persist_sync_loop() {
    while true; do
        sleep "$PERSIST_SYNC_SECONDS"
        sync_runtime_to_persist || true
    done
}

if [ "$(id -u)" = "0" ]; then
    if [ -n "$HERMES_UID" ] && [ "$HERMES_UID" != "$(id -u hermes)" ]; then
        echo "Changing hermes UID to $HERMES_UID"
        usermod -u "$HERMES_UID" hermes
    fi

    if [ -n "$HERMES_GID" ] && [ "$HERMES_GID" != "$(id -g hermes)" ]; then
        echo "Changing hermes GID to $HERMES_GID"
        groupmod -g "$HERMES_GID" hermes
    fi

    actual_hermes_uid=$(id -u hermes)
    for target_dir in "$PERSIST_HOME" "$RUNTIME_HOME"; do
        mkdir -p "$target_dir"
        if [ "$(stat -c %u "$target_dir" 2>/dev/null)" != "$actual_hermes_uid" ]; then
            echo "$target_dir is not owned by $actual_hermes_uid, fixing"
            chown -R hermes:hermes "$target_dir"
        fi
    done

    echo "Dropping root privileges"
    if command -v gosu >/dev/null 2>&1; then
        exec gosu hermes "$0" "$@"
    fi

    if command -v runuser >/dev/null 2>&1; then
        exec runuser -u hermes -- "$0" "$@"
    fi

    if command -v su >/dev/null 2>&1; then
        exec su -m -s /bin/bash hermes -c 'exec "$0" "$@"' -- "$0" "$@"
    fi

    echo "Failed to drop root privileges: gosu, runuser, and su are all unavailable" >&2
    exit 1
fi

source "${INSTALL_DIR}/.venv/bin/activate"
export HERMES_PERSIST_HOME="$PERSIST_HOME"
export HERMES_HOME="$RUNTIME_HOME"

mkdir -p "$PERSIST_HOME" "$RUNTIME_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

if [ ! -f "$PERSIST_HOME/.env" ]; then
    cp "$INSTALL_DIR/huggingface/.env.space.example" "$PERSIST_HOME/.env"
fi

if [ ! -f "$PERSIST_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/huggingface/config.space.yaml" "$PERSIST_HOME/config.yaml"
fi

if [ ! -f "$PERSIST_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$PERSIST_HOME/SOUL.md"
fi

sync_persist_to_runtime

if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

# Optional Weixin bootstrap for headless HF deployments.
# If Weixin is requested and credentials are missing, print the QR login flow
# into the Space logs, persist the returned credentials into /data/.env, then
# continue to start the gateway.
export HERMES_HOME="$PERSIST_HOME"
python3 - <<'PY'
import asyncio
import os
import sys

from gateway.platforms.weixin import check_weixin_requirements, qr_login
from hermes_cli.config import save_env_value, get_env_value


def truthy(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = str(value).strip().lower()
    if not normalized:
        return default
    return normalized in {"1", "true", "yes", "on"}


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

weixin_requested = truthy(os.getenv("WEIXIN_ENABLED"), False) or any(get_env_value(key) for key in intent_keys)
auto_qr_enabled = truthy(os.getenv("WEIXIN_AUTO_QR_LOGIN"), True)
account_id = get_env_value("WEIXIN_ACCOUNT_ID") or ""
token = get_env_value("WEIXIN_TOKEN") or ""

if not weixin_requested:
    sys.exit(0)

if account_id and token:
    print("Weixin bootstrap: existing credentials detected, skipping QR login.")
    sys.exit(0)

if not auto_qr_enabled:
    print("Weixin bootstrap: WEIXIN_AUTO_QR_LOGIN is disabled and credentials are missing.")
    sys.exit(1)

if not check_weixin_requirements():
    print("Weixin bootstrap failed: aiohttp and cryptography are required.")
    sys.exit(1)

hermes_home = os.getenv("HERMES_HOME", "/data")
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

cp "$PERSIST_HOME/.env" "$RUNTIME_HOME/.env"

# Sync process-level model overrides into /data/config.yaml so the gateway and
# background tasks use the same effective provider/model after restarts.
#
# Primary model variables (backward-compatible):
#   CUSTOM_OPENAI_BASE_URL / OPENAI_BASE_URL
#   HERMES_MODEL
#   OPENAI_API_KEY / ANTHROPIC_API_KEY / ANTHROPIC_APILKEY
#
# Secondary model variables:
#   SECONDARY_CUSTOM_OPENAI_BASE_URL / SECONDARY_OPENAI_BASE_URL
#   SECONDARY_HERMES_MODEL
#   SECONDARY_OPENAI_API_KEY / SECONDARY_ANTHROPIC_API_KEY / SECONDARY_ANTHROPIC_APILKEY
#
# Selector:
#   ACTIVE_CUSTOM_MODEL=primary|secondary
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
elif [ -n "${HERMES_INFERENCE_PROVIDER:-}" ]; then
    hermes config set model.provider "$HERMES_INFERENCE_PROVIDER"
fi

if [ -n "$SELECTED_MODEL_NAME" ]; then
    hermes config set model.default "$SELECTED_MODEL_NAME"
fi

# For custom OpenAI-compatible endpoints, Hermes naturally reads OPENAI_API_KEY.
# Some upstream services ask users to provide ANTHROPIC_API_KEY instead, and
# this deployment also tolerates the user's ANTHROPIC_APILKEY alias.
if [ "$ACTIVE_CUSTOM_MODEL" = "secondary" ]; then
    if [ -z "${OPENAI_API_KEY:-}" ]; then
        if [ -n "${SECONDARY_OPENAI_API_KEY:-}" ]; then
            export OPENAI_API_KEY="$SECONDARY_OPENAI_API_KEY"
        elif [ -n "${SECONDARY_ANTHROPIC_APILKEY:-}" ]; then
            export OPENAI_API_KEY="$SECONDARY_ANTHROPIC_APILKEY"
        elif [ -n "${SECONDARY_ANTHROPIC_API_KEY:-}" ]; then
            export OPENAI_API_KEY="$SECONDARY_ANTHROPIC_API_KEY"
        elif [ -n "${ANTHROPIC_APILKEY:-}" ]; then
            export OPENAI_API_KEY="$ANTHROPIC_APILKEY"
        elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            export OPENAI_API_KEY="$ANTHROPIC_API_KEY"
        fi
    fi
else
    if [ -z "${OPENAI_API_KEY:-}" ]; then
        if [ -n "${ANTHROPIC_APILKEY:-}" ]; then
            export OPENAI_API_KEY="$ANTHROPIC_APILKEY"
        elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
            export OPENAI_API_KEY="$ANTHROPIC_API_KEY"
        fi
    fi
fi

export API_SERVER_ENABLED="${API_SERVER_ENABLED:-true}"
export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"
export API_SERVER_PORT="${API_SERVER_PORT:-${PORT:-7860}}"
export API_SERVER_MODEL_NAME="${API_SERVER_MODEL_NAME:-Hermes-Agent}"

sync_persist_to_runtime

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
sync_runtime_to_persist || true

exit "$STATUS"
