# ================================================================ jdk21
# Eclipse Temurin JDK 21, sha256.
# Результат: /opt/jdk

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG JDK21_URL=https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.13_9.tar.gz
ARG JDK21_SHA256=d7f5d5cf865a2902b70ff549b97586a7d3f234e016f041ab447ea740c7d66d1c

RUN curl -fsSLo jdk.tar.gz "${JDK21_URL}" \
 && echo "${JDK21_SHA256}  jdk.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/jdk \
 && tar -xzf jdk.tar.gz -C /opt/jdk --strip-components=1 --no-same-owner \
 && rm jdk.tar.gz \
 && /opt/jdk/bin/java -version
