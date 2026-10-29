# ================================================================ pytest
# pytest как uv tool. База — тот же Debian с python3, что и в итоговом образе:
# venv uv tool ссылается на /usr/bin/python3.
# Зависит от: uv (--build-context uv=...)
# Результат: /opt/uv-tools, /opt/bin/pytest

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

ARG PYTEST_VERSION=9.1.1

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=uv /opt/bin/uv /usr/local/bin/uv

RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/opt/bin UV_PYTHON_DOWNLOADS=never \
    uv tool install --python /usr/bin/python3 "pytest==${PYTEST_VERSION}" \
 && /opt/bin/pytest --version
