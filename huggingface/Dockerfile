FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM tianon/gosu:1.19-trixie@sha256:3b176695959c71e123eb390d427efc665eeb561b1540e82679c15e992006b8b9 AS gosu_source
FROM debian:13.4

ARG HERMES_REPO=https://github.com/Viciy2023/hermes-agent.git
ARG HERMES_REF=main

ENV PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    HERMES_HOME=/data

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        ffmpeg \
        gcc \
        git \
        libffi-dev \
        nodejs \
        npm \
        procps \
        python3 \
        python3-dev \
        ripgrep && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

RUN git clone --depth 1 --branch ${HERMES_REF} ${HERMES_REPO} /opt/hermes
COPY huggingface/entrypoint.sh /opt/hermes/huggingface/entrypoint.sh
COPY huggingface/config.space.yaml /opt/hermes/huggingface/config.space.yaml
COPY huggingface/.env.space.example /opt/hermes/huggingface/.env.space.example
COPY huggingface/README.md /opt/hermes/huggingface/README.md
WORKDIR /opt/hermes

RUN chown -R hermes:hermes /opt/hermes
USER hermes

RUN uv venv /opt/hermes/.venv && \
    uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir -e ".[all]"

USER root
RUN chmod +x /opt/hermes/huggingface/entrypoint.sh

VOLUME ["/data"]
EXPOSE 7860
ENTRYPOINT ["/opt/hermes/huggingface/entrypoint.sh"]
