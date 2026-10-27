# ================================================================ go
# Go: официальный релиз с go.dev, sha256.
# Результат: /opt/go (в итоговом образе — /usr/local/go)

ARG DOWNLOADER_IMAGE=localhost/agent-box/downloader:latest
FROM ${DOWNLOADER_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GO_VERSION=1.27.3
ARG GO_SHA256=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40

RUN curl -fsSLo go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
 && echo "${GO_SHA256}  go.tar.gz" | sha256sum -c - \
 && tar -xzf go.tar.gz -C /opt --no-same-owner \
 && rm go.tar.gz \
 && /opt/go/bin/go version
