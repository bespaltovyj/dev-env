# ================================================================ claude
# Claude Code: официальный установщик claude.ai/install.sh (native-бинарник).
# Результат: /opt/bin/claude

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# stable | latest | конкретная версия, например 2.1.309
ARG CLAUDE_CODE_VERSION=stable

# Установщик кладёт бинарник в $HOME/.local; дальше переносим только сам бинарник
RUN curl -fsSL https://claude.ai/install.sh | HOME=/opt/claude bash -s -- "${CLAUDE_CODE_VERSION}" \
 && install -D -m 0755 "$(readlink -f /opt/claude/.local/bin/claude)" /opt/bin/claude \
 && /opt/bin/claude --version
