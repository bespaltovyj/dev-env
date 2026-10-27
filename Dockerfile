# syntax=docker/dockerfile:1.7
# ================================================================ agent-box
# Изолированное окружение для ИИ-агентов: Orca, Claude Code, dcg, Node.js, Python 3, uv, ruff,
# pytest, Java 17/21/25 (Temurin), Maven, Gradle, Go, kubectl, Helm.
#
# Каждый компонент собирается отдельным образом из stages/<группа>/<name>.Dockerfile
# (ai, go, jvm, k8s, python) и подключается сюда через
# --build-context <name>=docker-image://localhost/agent-box/<name>:latest.
# Собирать скриптом build.ps1 / build.sh, а не напрямую.

ARG DEBIAN_IMAGE=debian:trixie-slim
FROM ${DEBIAN_IMAGE}

ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# ================================================================ системные пакеты
# Базовые утилиты, git, компиляторы, Python 3 и pip
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client build-essential \
      tini tmux less procps jq ripgrep \
      python3 python3-pip python3-venv \
 && rm -rf /var/lib/apt/lists/*

# Orca: .deb подключается из образа orca без копирования в слой. CLI называется orca-ide.
# libasound2t64 нужен Electron, но не объявлен в зависимостях пакета.
RUN --mount=type=bind,from=orca,source=/opt/orca.deb,target=/tmp/orca.deb \
    apt-get update \
 && apt-get install -y --no-install-recommends /tmp/orca.deb libasound2t64 \
 && rm -rf /var/lib/apt/lists/*

# ================================================================ компоненты
COPY --from=node    /opt/node/       /usr/local/
COPY --from=claude  /opt/bin/claude  /usr/local/bin/claude
COPY --from=dcg     /opt/bin/dcg     /usr/local/bin/dcg
COPY --from=uv      /opt/bin/        /usr/local/bin/
COPY --from=ruff    /opt/bin/ruff    /usr/local/bin/ruff
COPY --from=pytest  /opt/uv-tools/   /opt/uv-tools/
COPY --from=pytest  /opt/bin/        /usr/local/bin/
COPY --from=kubectl /opt/bin/kubectl /usr/local/bin/kubectl
COPY --from=helm    /opt/bin/helm    /usr/local/bin/helm
COPY --from=go      /opt/go/         /usr/local/go/

# JDK в /usr/lib/jvm: там их автоматически находят тулчейны Gradle
COPY --from=jdk17   /opt/jdk/        /usr/lib/jvm/temurin-17/
COPY --from=jdk21   /opt/jdk/        /usr/lib/jvm/temurin-21/
COPY --from=jdk25   /opt/jdk/        /usr/lib/jvm/temurin-25/
COPY --from=maven   /opt/maven/      /opt/maven/
COPY --from=gradle  /opt/gradle/     /opt/gradle/

# Управляемые настройки Claude Code: хук dcg нельзя отключить из ~/.claude
COPY managed-settings.json /etc/claude-code/managed-settings.json

# Точка входа: tmux-сессия orca с `orca-ide serve` (отключается ORCA_SERVE=0)
COPY --chmod=755 entrypoint.sh /usr/local/bin/agent-entrypoint

# ================================================================ окружение
# Общие
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    EDITOR=vi

# Java: по умолчанию 25, остальные доступны через JAVA_<N>_HOME
ENV JAVA_HOME=/usr/lib/jvm/temurin-25 \
    JAVA_17_HOME=/usr/lib/jvm/temurin-17 \
    JAVA_21_HOME=/usr/lib/jvm/temurin-21 \
    JAVA_25_HOME=/usr/lib/jvm/temurin-25

# Maven / Gradle
ENV MAVEN_HOME=/opt/maven \
    M2_HOME=/opt/maven \
    GRADLE_HOME=/opt/gradle \
    GRADLE_USER_HOME=/home/agent/.gradle

# Go: тулчейн не скачивается сам (GOTOOLCHAIN=local), модули — в GOPATH пользователя
ENV GOROOT=/usr/local/go \
    GOPATH=/home/agent/go \
    GOTOOLCHAIN=local

# Node.js / npm: глобальные пакеты ставятся в домашний каталог, без root
ENV NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# Python / pip / uv
ENV PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_PREFERENCE=system

# Kubernetes / Helm
ENV KUBECONFIG=/home/agent/.kube/config

# Claude Code: версия фиксируется образом
ENV DISABLE_AUTOUPDATER=1

ENV PATH=/home/agent/.local/bin:/home/agent/.npm-global/bin:/home/agent/go/bin:/usr/local/go/bin:/usr/lib/jvm/temurin-25/bin:/opt/maven/bin:/opt/gradle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Login-shell (tmux, bash -l) берёт PATH из /etc/profile — вернуть PATH образа
RUN echo "export PATH=\"$PATH\"" > /etc/profile.d/00-agent-box-path.sh

# ================================================================ проверка
# Временный HOME, чтобы проверки не оставили файлов в /home/agent
RUN export HOME=/tmp/check GRADLE_USER_HOME=/tmp/check/.gradle \
 && node --version && npm --version && claude --version && dcg --version \
 && python3 --version && pip3 --version && uv --version && ruff --version && pytest --version \
 && git --version && gcc --version | head -1 \
 && java -version && mvn --version && gradle --version --no-daemon \
 && go version && kubectl version --client && helm version \
 && rm -rf /tmp/check

# ================================================================ пользователь
RUN groupadd --gid "${USER_GID}" agent \
 && useradd --uid "${USER_UID}" --gid agent --create-home --shell /bin/bash agent \
 && mkdir -p /workspaces \
 && chown agent:agent /workspaces

USER agent
WORKDIR /workspaces

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/agent-entrypoint"]
CMD ["bash"]
