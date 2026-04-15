#!/usr/bin/env python3
from pathlib import Path


WEIXIN_TARGET = Path("/opt/hermes/gateway/platforms/weixin.py")
RUN_TARGET = Path("/opt/hermes/gateway/run.py")
BASE_TARGET = Path("/opt/hermes/gateway/platforms/base.py")


WEIXIN_OLD = """    async def send_image_file(
        self,
        chat_id: str,
        path: str,
        caption: str = "",
        reply_to: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> SendResult:
        return await self.send_document(chat_id, path, caption=caption, metadata=metadata)
"""


WEIXIN_NEW = """    async def send_image_file(
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

    if WEIXIN_OLD not in text:
        print("HF patch warning: could not patch Weixin send_image_file block")
        return

    WEIXIN_TARGET.write_text(text.replace(WEIXIN_OLD, WEIXIN_NEW), encoding="utf-8")
    print("HF patch: applied Weixin send_image_file compatibility")


def patch_run() -> None:
    if not RUN_TARGET.exists():
        print(f"HF patch warning: {RUN_TARGET} not found; skipping gateway.run patch")
        return

    text = RUN_TARGET.read_text(encoding="utf-8")

    old_media = """                        await adapter.send_image_file(
                            chat_id=event.source.chat_id,
                            image_path=media_path,
                            metadata=_thread_meta,
                        )
"""
    new_media = """                        await adapter.send_image_file(
                            chat_id=event.source.chat_id,
                            path=media_path,
                            metadata=_thread_meta,
                        )
"""

    old_file = """                        await adapter.send_image_file(
                            chat_id=event.source.chat_id,
                            image_path=file_path,
                            metadata=_thread_meta,
                        )
"""
    new_file = """                        await adapter.send_image_file(
                            chat_id=event.source.chat_id,
                            path=file_path,
                            metadata=_thread_meta,
                        )
"""

    changed = False
    if old_media in text:
        text = text.replace(old_media, new_media)
        changed = True
    if old_file in text:
        text = text.replace(old_file, new_file)
        changed = True

    if not changed:
        if 'path=media_path' in text and 'path=file_path' in text:
            print("HF patch: gateway.run image send arguments already compatible")
            return
        print("HF patch warning: could not patch gateway.run image send arguments")
        return

    RUN_TARGET.write_text(text, encoding="utf-8")
    print("HF patch: applied gateway.run image send argument compatibility")


def patch_base() -> None:
    if not BASE_TARGET.exists():
        print(f"HF patch warning: {BASE_TARGET} not found; skipping platform base patch")
        return

    text = BASE_TARGET.read_text(encoding="utf-8")

    old_media = """                            media_result = await self.send_image_file(
                                chat_id=event.source.chat_id,
                                image_path=media_path,
                                metadata=_thread_metadata,
                            )
"""
    new_media = """                            media_result = await self.send_image_file(
                                chat_id=event.source.chat_id,
                                path=media_path,
                                metadata=_thread_metadata,
                            )
"""

    old_file = """                            await self.send_image_file(
                                chat_id=event.source.chat_id,
                                image_path=file_path,
                                metadata=_thread_metadata,
                            )
"""
    new_file = """                            await self.send_image_file(
                                chat_id=event.source.chat_id,
                                path=file_path,
                                metadata=_thread_metadata,
                            )
"""

    changed = False
    if old_media in text:
        text = text.replace(old_media, new_media)
        changed = True
    if old_file in text:
        text = text.replace(old_file, new_file)
        changed = True

    if not changed:
        if 'path=media_path' in text and 'path=file_path' in text:
            print("HF patch: gateway.platforms.base image send arguments already compatible")
            return
        print("HF patch warning: could not patch gateway.platforms.base image send arguments")
        return

    BASE_TARGET.write_text(text, encoding="utf-8")
    print("HF patch: applied gateway.platforms.base image send argument compatibility")


def main() -> None:
    patch_weixin()
    patch_run()
    patch_base()


if __name__ == "__main__":
    main()
