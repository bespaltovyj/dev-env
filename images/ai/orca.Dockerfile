# ================================================================ orca
# .deb Orca из официального релиза, sha256. Ставится в итоговом образе через apt,
# чтобы подтянуть зависимости Electron.
# Результат: /opt/orca.deb

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG ORCA_VERSION=1.4.237
ARG ORCA_SHA256=296ffd14345612be70ca09e9ab40f7ffbb7f842fb5794e1e6c1ebc324360cb5c

RUN curl -fsSLo /opt/orca.deb "https://github.com/stablyai/orca/releases/download/v${ORCA_VERSION}/orca-ide_${ORCA_VERSION}_amd64.deb" \
 && echo "${ORCA_SHA256}  /opt/orca.deb" | sha256sum -c -
