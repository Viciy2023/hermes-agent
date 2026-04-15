#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.error
import urllib.request


SIZE_MAP = {
    "1:1": "1024x1024",
    "16:9": "1600x900",
    "9:16": "900x1600",
}


def _fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        _fail(f"Missing required environment variable: {name}")
    return value


def _post_json(url: str, api_key: str, payload: dict) -> dict:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        _fail(f"Image generation API error {exc.code}: {detail}")
    except urllib.error.URLError as exc:
        _fail(f"Image generation request failed: {exc}")

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        _fail(f"Image generation returned invalid JSON: {exc}: {body[:300]}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate an image via qwen2API and emit a MEDIA path.")
    parser.add_argument("--prompt", required=True, help="Image prompt")
    parser.add_argument("--ratio", choices=sorted(SIZE_MAP.keys()), default="1:1", help="Aspect ratio")
    args = parser.parse_args()

    base_url = _env("TEXT_TO_IMAGE_OPENAI_BASE_URL").rstrip("/")
    api_key = _env("TEXT_TO_IMAGE_OPENAI_API_KEY")
    model = _env("TEXT_TO_IMAGE_MODEL")
    prompt = args.prompt.strip()
    if not prompt:
        _fail("Prompt must not be empty")

    payload = {
        "model": model,
        "prompt": prompt,
        "n": 1,
        "size": SIZE_MAP[args.ratio],
        "response_format": "url",
    }

    result = _post_json(f"{base_url}/images/generations", api_key, payload)
    data = result.get("data") or []
    if not data or not isinstance(data, list):
        _fail(f"Image generation succeeded but returned no data: {json.dumps(result, ensure_ascii=False)[:500]}")

    first = data[0] or {}
    image_url = str(first.get("url") or "").strip()
    if not image_url:
        _fail(f"Image generation returned no image URL: {json.dumps(result, ensure_ascii=False)[:500]}")

    print(f"![generated]({image_url})")


if __name__ == "__main__":
    main()
