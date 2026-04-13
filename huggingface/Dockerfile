FROM nousresearch/hermes-agent:latest

ARG HERMES_REPO=https://github.com/NousResearch/hermes-agent.git
ARG HERMES_REF=main

ENV PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    HERMES_HOME=/data

# Keep a source-build fallback reference available as build args, but default to
# the official published image to reduce HF build cost.
COPY huggingface/ /tmp/huggingface/

RUN mkdir -p /opt/hermes/huggingface && \
    cp /tmp/huggingface/entrypoint.sh /opt/hermes/huggingface/entrypoint.sh && \
    cp /tmp/huggingface/config.space.yaml /opt/hermes/huggingface/config.space.yaml && \
    cp /tmp/huggingface/.env.space.example /opt/hermes/huggingface/.env.space.example

WORKDIR /opt/hermes

RUN chmod +x /opt/hermes/huggingface/entrypoint.sh

VOLUME ["/data"]
EXPOSE 7860
ENTRYPOINT ["/opt/hermes/huggingface/entrypoint.sh"]
