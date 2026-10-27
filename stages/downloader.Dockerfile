# ================================================================ downloader
# Общая база для стадий-загрузчиков: curl, ca-certificates, xz, unzip.
# Образ: localhost/agent-box/downloader

ARG DEBIAN_IMAGE=debian:trixie-slim
FROM ${DEBIAN_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils unzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /dl
