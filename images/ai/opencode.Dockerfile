# ================================================================ opencode
# opencode (anomalyco/opencode): официальный установщик opencode.ai/install.
# Скрипт кладёт бинарник в $HOME/.opencode/bin и сам определяет платформу (musl/baseline); переносим в /opt/bin.
# Результат: /opt/bin/opencode

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# версия релиза github.com/anomalyco/opencode, например 1.0.180; переопределяется --build-arg OPENCODE_VERSION=...
# Пусто — latest на момент сборки
ARG OPENCODE_VERSION=

ENV VERSION=${OPENCODE_VERSION}

RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path \
 && install -D -m 0755 /root/.opencode/bin/opencode /opt/bin/opencode \
 && rm -rf /root/.opencode \
 && /opt/bin/opencode --version
