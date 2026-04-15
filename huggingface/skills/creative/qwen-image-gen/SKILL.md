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
3. Find the skill directory:
   ```bash
   SKILL_DIR=$(dirname "$(find ~/.hermes/skills -path '*/qwen-image-gen/SKILL.md' 2>/dev/null | head -1)")
   ```
4. Run the helper script:
   ```bash
   python "$SKILL_DIR/scripts/generate_image.py" --prompt "<prompt>" --ratio "<ratio>"
   ```
5. On success, the script prints a single markdown image tag like `![generated](https://...)`.
6. Return that markdown image tag unchanged so Hermes extracts the remote image URL and delivers it to the current channel.

## Rules

- Do not claim success unless the script returned a markdown image tag with a real remote URL.
- Do not return a plain text explanation if the script succeeded. Return the markdown image tag unchanged.
- If the script fails, explain the error briefly and do not pretend the image was sent.
- Prefer this skill over free-form image promises when the user asks for image generation.
