# ================================================================ jdk25
# Eclipse Temurin JDK 25, sha256. В итоговом образе это JAVA_HOME по умолчанию.
# Результат: /opt/jdk

ARG DOWNLOADER_IMAGE=localhost/agent-box/downloader:latest
FROM ${DOWNLOADER_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG JDK25_URL=https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz
ARG JDK25_SHA256=68982529869257d0ee6b824ec5aa270ff8b118bb438670da0b97ebdab178d7fb

RUN curl -fsSLo jdk.tar.gz "${JDK25_URL}" \
 && echo "${JDK25_SHA256}  jdk.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/jdk \
 && tar -xzf jdk.tar.gz -C /opt/jdk --strip-components=1 --no-same-owner \
 && rm jdk.tar.gz \
 && /opt/jdk/bin/java -version
