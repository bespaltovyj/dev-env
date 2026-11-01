# ================================================================ kimi
# Kimi Code CLI: официальный установщик code.kimi.com/kimi-code/install.sh (нативный бинарник linux-x64).
# Результат: /opt/bin/kimi

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# версия с code.kimi.com/kimi-code/latest; переопределяется --build-arg KIMI_VERSION=...
ARG KIMI_VERSION=0.4.0

# Установщик кладёт бинарник в $KIMI_INSTALL_DIR/bin и проверяет sha256; запись в shell-rc не нужна
# (PATH задан образом). Автообновление и телеметрия выключены в итоговом образе.
RUN curl -fsSL https://code.kimi.com/kimi-code/install.sh \
      | KIMI_INSTALL_DIR=/opt KIMI_NO_MODIFY_PATH=1 KIMI_VERSION="${KIMI_VERSION}" bash \
 && /opt/bin/kimi --version
