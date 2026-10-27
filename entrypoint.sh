#!/bin/bash
# Точка входа agent-box: прокси для Maven/Gradle, фоновая tmux-сессия orca с `orca-ide serve`,
# затем основная команда контейнера.
#   ORCA_SERVE=0          не запускать orca serve
#   ORCA_PORT=6769        порт сервера (6768 на Windows занят десктопным Orca)
#   ORCA_PAIRING_ADDRESS  адрес для клиента (по умолчанию ws://127.0.0.1:$ORCA_PORT)
#   HTTPS_PROXY           http://host:port — Maven и Gradle переменные окружения не читают,
#                         им прокси прописывается в ~/.m2/settings.xml и ~/.gradle/gradle.properties
set -euo pipefail

# Только если файлов ещё нет: свои настройки пользователя не перезаписываются
if [[ "${HTTPS_PROXY:-}" =~ ^https?://([^:/]+):([0-9]+) ]]; then
  proxy_host="${BASH_REMATCH[1]}"
  proxy_port="${BASH_REMATCH[2]}"
  no_proxy_java="localhost|127.0.0.1"

  if [[ ! -e "$HOME/.m2/settings.xml" ]]; then
    mkdir -p "$HOME/.m2"
    cat >"$HOME/.m2/settings.xml" <<EOF
<!-- Создано agent-entrypoint из HTTPS_PROXY -->
<settings>
  <proxies>
    <proxy><id>https</id><active>true</active><protocol>https</protocol><host>$proxy_host</host><port>$proxy_port</port><nonProxyHosts>$no_proxy_java</nonProxyHosts></proxy>
    <proxy><id>http</id><active>true</active><protocol>http</protocol><host>$proxy_host</host><port>$proxy_port</port><nonProxyHosts>$no_proxy_java</nonProxyHosts></proxy>
  </proxies>
</settings>
EOF
  fi

  gradle_props="${GRADLE_USER_HOME:-$HOME/.gradle}/gradle.properties"
  if [[ ! -e "$gradle_props" ]]; then
    mkdir -p "$(dirname "$gradle_props")"
    cat >"$gradle_props" <<EOF
# Создано agent-entrypoint из HTTPS_PROXY
systemProp.http.proxyHost=$proxy_host
systemProp.http.proxyPort=$proxy_port
systemProp.https.proxyHost=$proxy_host
systemProp.https.proxyPort=$proxy_port
systemProp.http.nonProxyHosts=$no_proxy_java
EOF
  fi
fi

if [[ "${ORCA_SERVE:-1}" != 0 ]]; then
  port="${ORCA_PORT:-6769}"
  address="${ORCA_PAIRING_ADDRESS:-ws://127.0.0.1:$port}"
  # remain-on-exit: если сервер упадёт, его вывод останется в сессии
  tmux new-session -d -s orca \
    "orca-ide serve --port $port --pairing-address $address" \; \
    set-option -t orca remain-on-exit on
fi

exec "$@"
