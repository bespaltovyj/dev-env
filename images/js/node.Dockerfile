# ================================================================ node
# Node.js + npm: официальный бинарный релиз, sha256.
# Результат: /opt/node

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NODE_VERSION=24.22.1
ARG NODE_SHA256=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6

RUN curl -fsSLo node.tar.xz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
 && echo "${NODE_SHA256}  node.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/node \
 && tar -xJf node.tar.xz -C /opt/node --strip-components=1 --no-same-owner \
 && rm -f /opt/node/{CHANGELOG.md,README.md,LICENSE} node.tar.xz \
 && /opt/node/bin/node --version
