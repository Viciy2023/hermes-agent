QWEN_IMAGE_GENERATE = {
    "name": "qwen_image_generate",
    "description": (
        "Generate an image through the dedicated text-to-image endpoint. "
        "Use this when the user asks to draw, create, or generate an image. "
        "Returns a MEDIA path for native channel delivery."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "prompt": {
                "type": "string",
                "description": "Image prompt describing what to generate.",
            },
            "ratio": {
                "type": "string",
                "enum": ["1:1", "16:9", "9:16"],
                "description": "Aspect ratio. Default is 1:1 if omitted.",
            },
        },
        "required": ["prompt"],
    },
}
