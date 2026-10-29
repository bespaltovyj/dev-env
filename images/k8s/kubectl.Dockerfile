# ================================================================ kubectl
# Kubernetes CLI с dl.k8s.io, sha256.
# Результат: /opt/bin/kubectl

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG KUBECTL_VERSION=v1.37.1
ARG KUBECTL_SHA256=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8

RUN curl -fsSLo kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && echo "${KUBECTL_SHA256}  kubectl" | sha256sum -c - \
 && install -D -m 0755 kubectl /opt/bin/kubectl \
 && /opt/bin/kubectl version --client
