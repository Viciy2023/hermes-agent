ARG HERMES_IMAGE=nousresearch/hermes-agent:latest
FROM ${HERMES_IMAGE}

USER root

COPY huggingface/entrypoint.sh /opt/hermes/huggingface/entrypoint.sh
COPY huggingface/config.space.yaml /opt/hermes/huggingface/config.space.yaml
COPY huggingface/.env.space.example /opt/hermes/huggingface/.env.space.example
COPY huggingface/README.md /opt/hermes/huggingface/README.md

RUN chmod +x /opt/hermes/huggingface/entrypoint.sh

ENV PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    HERMES_HOME=/data

VOLUME ["/data"]
EXPOSE 7860
ENTRYPOINT ["/opt/hermes/huggingface/entrypoint.sh"]
