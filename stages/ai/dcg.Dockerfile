# ================================================================ dcg
# Destructive Command Guard: статический musl-бинарник, sha256.
# Результат: /opt/bin/dcg

ARG DOWNLOADER_IMAGE=localhost/agent-box/downloader:latest
FROM ${DOWNLOADER_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DCG_VERSION=0.15.3
ARG DCG_SHA256=dc7dcec9679f74ac3e6990959771ca0c84168eba658eff64fe9e63f917a84cc4

RUN curl -fsSLo dcg.tar.xz "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${DCG_VERSION}/dcg-x86_64-unknown-linux-musl.tar.xz" \
 && echo "${DCG_SHA256}  dcg.tar.xz" | sha256sum -c - \
 && tar -xJf dcg.tar.xz \
 && install -D -m 0755 "$(find . -type f -name dcg | head -1)" /opt/bin/dcg \
 && /opt/bin/dcg --version
