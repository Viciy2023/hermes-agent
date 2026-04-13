#!/bin/bash
set -e

PERSIST_HOME_RAW="${HERMES_HOME:-/data}"
PERSIST_HOME="$(printf '%s' "$PERSIST_HOME_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
RUNTIME_HOME_RAW="${HERMES_RUNTIME_HOME:-/tmp/hermes-runtime}"
RUNTIME_HOME="$(printf '%s' "$RUNTIME_HOME_RAW" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
PERSIST_SYNC_SECONDS="${HERMES_PERSIST_SYNC_SECONDS:-120}"
INSTALL_DIR="/opt/hermes"

sync_bidirectional_state() {
    python3 - <<'PY'
import os
from pathlib import Path

from huggingface.runtime_state import apply_sync_actions, plan_bidirectional_sync

runtime_root = Path(os.environ["RUNTIME_HOME"])
persist_root = Path(os.environ["PERSIST_HOME"])
actions = plan_bidirectional_sync(runtime_root, persist_root)
if actions:
    apply_sync_actions(runtime_root, persist_root, actions)
PY
}

start_persist_sync_loop() {
    while true; do
        sleep "$PERSIST_SYNC_SECONDS"
        sync_bidirectional_state || true
    done
}

mkdir -p "$PERSIST_HOME" "$RUNTIME_HOME"

source "${INSTALL_DIR}/.venv/bin/activate"
export HERMES_PERSIST_HOME="$PERSIST_HOME"
export HERMES_HOME="$RUNTIME_HOME"
export PERSIST_HOME RUNTIME_HOME INSTALL_DIR

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

sync_bidirectional_state

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
from huggingface.runtime_state import should_run_weixin_qr_login, validate_weixin_credentials


def truthy(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    normalized = str(value).strip().lower()
    if not normalized:
        return default
    return normalized in {"1", "true", "yes", "on"}


env_values = {key: get_env_value(key) or os.getenv(key) for key in [
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
]}

should_run_qr, reason = asyncio.run(
    should_run_weixin_qr_login(env_values, validate_weixin_credentials)
)

if reason == "not_requested":
    sys.exit(0)

if not should_run_qr and reason == "valid_credentials":
    print("Weixin bootstrap: existing credentials detected and validated, skipping QR login.")
    sys.exit(0)

if not should_run_qr:
    if reason == "invalid_credentials_auto_qr_disabled":
        print("Weixin bootstrap: saved credentials are invalid and WEIXIN_AUTO_QR_LOGIN is disabled.")
    elif reason == "missing_credentials_auto_qr_disabled":
        print("Weixin bootstrap: WEIXIN_AUTO_QR_LOGIN is disabled and credentials are missing.")
    else:
        print(f"Weixin bootstrap skipped: {reason}")
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

python3 - <<'PY'
import os
from pathlib import Path
import shutil

persist_env = Path(os.environ["PERSIST_HOME"]) / ".env"
runtime_env = Path(os.environ["RUNTIME_HOME"]) / ".env"
if persist_env.exists():
    runtime_env.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(persist_env, runtime_env)
PY

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

sync_bidirectional_state

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
sync_bidirectional_state || true

exit "$STATUS"
