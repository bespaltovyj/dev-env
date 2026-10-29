# ================================================================ maven
# Apache Maven, sha512.
# Результат: /opt/maven

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG MAVEN_VERSION=3.10.0
ARG MAVEN_SHA512=908b1501bfb420bf7c8affb855534a9c407fd6099367bfb9f2f2dcb8e9799102bffb84518cde74c679bd76870247c6528683abdd620581bffa90f95d92d175aa

RUN curl -fsSLo maven.tar.gz "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
 && echo "${MAVEN_SHA512}  maven.tar.gz" | sha512sum -c - \
 && mkdir -p /opt/maven \
 && tar -xzf maven.tar.gz -C /opt/maven --strip-components=1 --no-same-owner \
 && rm maven.tar.gz
