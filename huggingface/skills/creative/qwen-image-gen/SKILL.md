---
name: qwen-image-gen
description: Generate an image with a qwen2API-compatible endpoint and return it as a native image attachment to the current channel.
version: 1.0.0
author: hermes-hf
license: MIT
metadata:
  hermes:
    tags: [creative, images, qwen, media]
    category: creative
---

# Qwen Image Generation

Generate an image with the dedicated text-to-image endpoint and send it back to the current channel.

## When to Use

- The user asks to generate, draw, or create an image
- The user explicitly asks to use the Qwen image skill
- The user wants the image delivered directly back to the current conversation channel

## Required Environment

This skill depends on these environment variables being configured in the runtime:

- `TEXT_TO_IMAGE_OPENAI_BASE_URL`
- `TEXT_TO_IMAGE_OPENAI_API_KEY`
- `TEXT_TO_IMAGE_MODEL`

The skill does not hardcode the endpoint, API key, or model value.

## Supported Ratios

- `1:1`
- `16:9`
- `9:16`

If the user does not specify a ratio, default to `1:1`.

## Procedure

1. Extract the image prompt from the user request.
2. Choose a ratio: `1:1`, `16:9`, or `9:16`.
3. Call the plugin tool `qwen_image_generate` with:
   - `prompt`
   - `ratio`
4. Wait for the real tool result.
5. If the tool succeeds, it returns JSON containing a real `media_tag` like `MEDIA:/absolute/path.png`.
6. Return that `media_tag` unchanged so Hermes delivers the image natively to the current channel.

## Rules

- Do not invent or guess a `MEDIA:` path.
- Do not simulate script execution.
- Do not fabricate success.
- Do not claim success unless the `qwen_image_generate` tool returned a real `media_tag`.
- If the tool succeeds, return the `media_tag` unchanged.
- If the script fails, explain the error briefly and do not pretend the image was sent.
- Prefer this skill over free-form image promises when the user asks for image generation.
