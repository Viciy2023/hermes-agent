#!/usr/bin/env python3
import re
from pathlib import Path


WEIXIN_TARGET = Path("/opt/hermes/gateway/platforms/weixin.py")
RUN_TARGET = Path("/opt/hermes/gateway/run.py")


WEIXIN_RE = re.compile(
    r"""(?ms)^\s{4}async def send_image_file\(\n"
    r"\s{8}self,\n"
    r"\s{8}chat_id: str,\n"
    r"\s{8}path: str,\n"
    r"\s{8}caption: str = \"\",\n"
    r"\s{8}reply_to: Optional\[str\] = None,\n"
    r"\s{8}metadata: Optional\[Dict\[str, Any\]\] = None,\n"
    r"\s{4}\) -> SendResult:\n"
    r"\s{8}return await self.send_document\(chat_id, path, caption=caption, metadata=metadata\)\n"""
)


WEIXIN_REPLACEMENT = """    async def send_image_file(
        self,
        chat_id: str,
        path: Optional[str] = None,
        caption: str = "",
        reply_to: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        image_path: Optional[str] = None,
        **kwargs,
    ) -> SendResult:
        effective_path = image_path or path
        if not effective_path:
            return SendResult(success=False, error="Missing image path")
        return await self.send_document(chat_id, effective_path, caption=caption, metadata=metadata)
"""


def patch_weixin() -> None:
    if not WEIXIN_TARGET.exists():
        print(f"HF patch warning: {WEIXIN_TARGET} not found; skipping Weixin patch")
        return

    text = WEIXIN_TARGET.read_text(encoding="utf-8")
    if "image_path: Optional[str] = None" in text:
        print("HF patch: Weixin send_image_file compatibility already present")
        return

    patched, count = WEIXIN_RE.subn(WEIXIN_REPLACEMENT, text, count=1)
    if count != 1:
        print("HF patch warning: could not patch Weixin send_image_file block")
        return

    WEIXIN_TARGET.write_text(patched, encoding="utf-8")
    print("HF patch: applied Weixin send_image_file compatibility")


def patch_run() -> None:
    if not RUN_TARGET.exists():
        print(f"HF patch warning: {RUN_TARGET} not found; skipping gateway.run patch")
        return

    text = RUN_TARGET.read_text(encoding="utf-8")
    if 'path=media_path' in text or 'path=file_path' in text:
        print("HF patch: gateway.run image send arguments already compatible")
        return

    patched = text.replace('image_path=media_path,', 'path=media_path,')
    patched = patched.replace('image_path=file_path,', 'path=file_path,')

    if patched == text:
        print("HF patch warning: could not patch gateway.run image send arguments")
        return

    RUN_TARGET.write_text(patched, encoding="utf-8")
    print("HF patch: applied gateway.run image send argument compatibility")


def main() -> None:
    patch_weixin()
    patch_run()


if __name__ == "__main__":
    main()
