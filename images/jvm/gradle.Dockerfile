# ================================================================ gradle
# Gradle, sha256.
# Результат: /opt/gradle

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GRADLE_VERSION=9.8.2
ARG GRADLE_SHA256=21bd5da2de49b642904077f38c0efdc7778e92b3ed0889392dca61b97e389607

RUN curl -fsSLo gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
 && echo "${GRADLE_SHA256}  gradle.zip" | sha256sum -c - \
 && unzip -q gradle.zip -d /tmp/gradle \
 && cp -a "/tmp/gradle/gradle-${GRADLE_VERSION}" /opt/gradle \
 && rm -rf gradle.zip /tmp/gradle
