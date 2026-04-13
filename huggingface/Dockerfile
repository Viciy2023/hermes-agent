ARG HERMES_IMAGE=nousresearch/hermes-agent:latest
FROM ${HERMES_IMAGE}

USER root

# The upstream runtime image used by HF Spaces may not include the non-root
# hermes account expected by our HF entrypoint, so create/repair it here.
RUN set -eux; \
    if ! getent group hermes >/dev/null; then groupadd -g 10000 hermes; fi; \
    if ! getent passwd hermes >/dev/null; then useradd -u 10000 -g 10000 -m -d /data hermes; fi

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
