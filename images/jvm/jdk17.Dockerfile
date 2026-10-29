# ================================================================ jdk17
# Eclipse Temurin JDK 17, sha256.
# Результат: /opt/jdk

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG JDK17_URL=https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.21%2B9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.21_9.tar.gz
ARG JDK17_SHA256=8b9b611d917e3dfd8419d3566b5949226f69b052fed7e109c1368add1dfe8711

RUN curl -fsSLo jdk.tar.gz "${JDK17_URL}" \
 && echo "${JDK17_SHA256}  jdk.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/jdk \
 && tar -xzf jdk.tar.gz -C /opt/jdk --strip-components=1 --no-same-owner \
 && rm jdk.tar.gz \
 && /opt/jdk/bin/java -version
