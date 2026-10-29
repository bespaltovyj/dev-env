# ================================================================ uv
# uv / uvx от Astral: статический musl-бинарник, sha256.
# Результат: /opt/bin/uv, /opt/bin/uvx

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG UV_VERSION=0.13.5
ARG UV_SHA256=57ef9d9ccb01fb1bd998df995b0dd221b52f7d7841fbea93f2d4463bf61fb7a9

RUN curl -fsSLo uv.tar.gz "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-musl.tar.gz" \
 && echo "${UV_SHA256}  uv.tar.gz" | sha256sum -c - \
 && tar -xzf uv.tar.gz --strip-components=1 \
 && install -D -m 0755 uv /opt/bin/uv \
 && install -D -m 0755 uvx /opt/bin/uvx \
 && /opt/bin/uv --version
