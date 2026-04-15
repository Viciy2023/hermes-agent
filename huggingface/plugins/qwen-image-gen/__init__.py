from . import schemas, tools


def register(ctx):
    ctx.register_tool(
        name="qwen_image_generate",
        toolset="plugin_qwen_image_gen",
        schema=schemas.QWEN_IMAGE_GENERATE,
        handler=tools.qwen_image_generate,
        description="Generate an image through the dedicated text-to-image endpoint and return a media attachment path.",
        emoji="🖼️",
    )
