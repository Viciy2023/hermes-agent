#!/usr/bin/env python3
from pathlib import Path


TARGET = Path("/opt/hermes/gateway/platforms/weixin.py")


def main() -> None:
    if not TARGET.exists():
        print(f"HF patch warning: {TARGET} not found; skipping Weixin patch")
        return

    text = TARGET.read_text(encoding="utf-8")
    marker = "        return await self.send_document(chat_id, path, caption=caption, metadata=metadata)"
    if "image_path: Optional[str] = None" in text:
        print("HF patch: Weixin send_image_file compatibility already present")
        return

    old = """    async def send_image_file(\n        self,\n        chat_id: str,\n        path: str,\n        caption: str = \"\",\n        reply_to: Optional[str] = None,\n        metadata: Optional[Dict[str, Any]] = None,\n    ) -> SendResult:\n        return await self.send_document(chat_id, path, caption=caption, metadata=metadata)\n"""
    new = """    async def send_image_file(\n        self,\n        chat_id: str,\n        path: Optional[str] = None,\n        caption: str = \"\",\n        reply_to: Optional[str] = None,\n        metadata: Optional[Dict[str, Any]] = None,\n        image_path: Optional[str] = None,\n        **kwargs,\n    ) -> SendResult:\n        effective_path = image_path or path\n        if not effective_path:\n            return SendResult(success=False, error=\"Missing image path\")\n        return await self.send_document(chat_id, effective_path, caption=caption, metadata=metadata)\n"""

    if old not in text:
        print("HF patch warning: expected Weixin send_image_file block not found; skipping patch")
        return

    TARGET.write_text(text.replace(old, new), encoding="utf-8")
    print("HF patch: applied Weixin send_image_file compatibility")


if __name__ == "__main__":
    main()
