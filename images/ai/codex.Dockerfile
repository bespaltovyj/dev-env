# ================================================================ codex
# OpenAI Codex CLI: нативный статический бинарник (musl) из релизов github.com/openai/codex.
# Результат: /opt/bin/codex

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# тег релиза github.com/openai/codex; переопределяется --build-arg CODEX_VERSION=...
ARG CODEX_VERSION=rust-v0.166.0

RUN curl -fsSLo codex.tar.gz "https://github.com/openai/codex/releases/download/${CODEX_VERSION}/codex-x86_64-unknown-linux-musl.tar.gz" \
 && mkdir -p /tmp/codex \
 && tar -xzf codex.tar.gz -C /tmp/codex \
 && bin="$(find /tmp/codex -type f -perm -u+x | head -n 1)" \
 && install -D -m 0755 "$bin" /opt/bin/codex \
 && rm -rf /tmp/codex codex.tar.gz \
 && /opt/bin/codex --version
