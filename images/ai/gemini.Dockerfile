# ================================================================ gemini
# Gemini CLI (Google): официальный npm-пакет @google/gemini-cli, версия зафиксирована.
# Node нужен только при сборке — подключается из образа node (--build-context node=...).
# Результат: /opt/gemini (bin/gemini → lib/node_modules/...)

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# версия с registry.npmjs.org; переопределяется --build-arg GEMINI_VERSION=...
ARG GEMINI_VERSION=0.66.0

COPY --from=node /opt/node/ /opt/node/
ENV PATH=/opt/node/bin:$PATH

RUN npm install -g --prefix /opt/gemini --cache /tmp/npm-cache "@google/gemini-cli@${GEMINI_VERSION}" \
 && /opt/gemini/bin/gemini --version
