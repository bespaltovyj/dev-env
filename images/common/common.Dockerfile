# ================================================================ common
# Базовый образ для всех остальных: Debian, apt только по https, ca-certificates, curl, xz, unzip.
# На нём собираются компоненты, итоговый образ и egress. Образ: localhost/agent-box/common

ARG DEBIAN_IMAGE=debian:trixie-slim
# Корневые сертификаты для первого apt по https (в debian:trixie-slim их нет)
ARG CA_IMAGE=docker.io/library/buildpack-deps:trixie-curl
FROM ${CA_IMAGE} AS ca
FROM ${DEBIAN_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# apt только по https: источники из settings/apt (--build-context settings=settings), других в образе нет.
# ca-certificates ставится с сертификатами из образа ca, дальше — со своими
RUN rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*
COPY --from=settings apt/debian.sources /etc/apt/sources.list.d/debian.sources

RUN --mount=type=bind,from=ca,source=/etc/ssl/certs/ca-certificates.crt,target=/tmp/ca.crt \
    apt-get -o Acquire::https::CAInfo=/tmp/ca.crt update \
 && apt-get -o Acquire::https::CAInfo=/tmp/ca.crt install -y --no-install-recommends ca-certificates \
 && apt-get install -y --no-install-recommends curl xz-utils unzip \
 && rm -rf /var/lib/apt/lists/*

# Рабочая папка компонентов для скачанных архивов
WORKDIR /dl
