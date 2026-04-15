import json
import os
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


SIZE_MAP = {
    "1:1": "1024x1024",
    "16:9": "1600x900",
    "9:16": "900x1600",
}


def _error(message: str) -> str:
    return json.dumps({"success": False, "error": message}, ensure_ascii=False)


def _env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
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
        raise RuntimeError(f"Image generation API error {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Image generation request failed: {exc}") from exc

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Image generation returned invalid JSON: {exc}: {body[:300]}") from exc


def _download_file(url: str) -> Path:
    parsed = urllib.parse.urlparse(url)
    suffix = Path(parsed.path).suffix or ".png"
    output_dir = Path(tempfile.gettempdir()) / "hermes-qwen-image-gen"
    output_dir.mkdir(parents=True, exist_ok=True)
    fd, temp_path = tempfile.mkstemp(prefix="qwen-image-", suffix=suffix, dir=output_dir)
    os.close(fd)
    path = Path(temp_path)

    try:
        with urllib.request.urlopen(url, timeout=180) as response:
            path.write_bytes(response.read())
    except Exception as exc:
        if path.exists():
            path.unlink(missing_ok=True)
        raise RuntimeError(f"Failed to download generated image: {exc}") from exc

    return path


def qwen_image_generate(args: dict, **kwargs) -> str:
    try:
        base_url = _env("TEXT_TO_IMAGE_OPENAI_BASE_URL").rstrip("/")
        api_key = _env("TEXT_TO_IMAGE_OPENAI_API_KEY")
        model = _env("TEXT_TO_IMAGE_MODEL")
        prompt = str(args.get("prompt") or "").strip()
        ratio = str(args.get("ratio") or "1:1").strip() or "1:1"

        if not prompt:
            return _error("Prompt must not be empty")
        if ratio not in SIZE_MAP:
            return _error(f"Unsupported ratio: {ratio}")

        payload = {
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": SIZE_MAP[ratio],
            "response_format": "url",
        }

        result = _post_json(f"{base_url}/images/generations", api_key, payload)
        data = result.get("data") or []
        if not data or not isinstance(data, list):
            return _error(f"Image generation succeeded but returned no data: {json.dumps(result, ensure_ascii=False)[:500]}")

        first = data[0] or {}
        image_url = str(first.get("url") or "").strip()
        if not image_url:
            return _error(f"Image generation returned no image URL: {json.dumps(result, ensure_ascii=False)[:500]}")

        local_path = _download_file(image_url)
        return json.dumps(
            {
                "success": True,
                "prompt": prompt,
                "ratio": ratio,
                "image_url": image_url,
                "media_tag": f"MEDIA:{local_path}",
            },
            ensure_ascii=False,
        )
    except Exception as exc:
        return _error(str(exc))
