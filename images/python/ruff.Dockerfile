# ================================================================ ruff
# ruff: линтер/форматтер Python, статический musl-бинарник, sha256.
# Результат: /opt/bin/ruff

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG RUFF_VERSION=0.17.2
ARG RUFF_SHA256=d6407f429ef15e558cbe980d30a67f27d02e3d2f72780be141ee006b2fdf7df3

RUN curl -fsSLo ruff.tar.gz "https://github.com/astral-sh/ruff/releases/download/${RUFF_VERSION}/ruff-x86_64-unknown-linux-musl.tar.gz" \
 && echo "${RUFF_SHA256}  ruff.tar.gz" | sha256sum -c - \
 && tar -xzf ruff.tar.gz --strip-components=1 \
 && install -D -m 0755 ruff /opt/bin/ruff \
 && /opt/bin/ruff --version
