# ================================================================ helm
# Helm с get.helm.sh, sha256.
# Результат: /opt/bin/helm

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG HELM_VERSION=v4.3.1
ARG HELM_SHA256=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b

RUN curl -fsSLo helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
 && echo "${HELM_SHA256}  helm.tar.gz" | sha256sum -c - \
 && tar -xzf helm.tar.gz --strip-components=1 \
 && install -D -m 0755 helm /opt/bin/helm \
 && /opt/bin/helm version
