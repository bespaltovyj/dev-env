# ================================================================ qwen
# Qwen Code (Alibaba): официальный npm-пакет @qwen-code/qwen-code, версия зафиксирована.
# Node нужен только при сборке — подключается из образа node (--build-context node=...).
# Результат: /opt/qwen (bin/qwen → lib/node_modules/...)

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# версия с registry.npmjs.org; переопределяется --build-arg QWEN_VERSION=...
ARG QWEN_VERSION=0.26.5

COPY --from=node /opt/node/ /opt/node/
ENV PATH=/opt/node/bin:$PATH

RUN npm install -g --prefix /opt/qwen --cache /tmp/npm-cache "@qwen-code/qwen-code@${QWEN_VERSION}" \
 && /opt/qwen/bin/qwen --version
