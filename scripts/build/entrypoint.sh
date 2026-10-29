#!/bin/bash
# Точка входа agent-box: прокси для Maven/Gradle, фоновая tmux-сессия orca с `orca-ide serve`,
# затем основная команда контейнера.
#   ORCA_SERVE=0          не запускать orca serve
#   ORCA_PORT=6769        порт сервера (6768 на Windows занят десктопным Orca)
#   ORCA_PAIRING_ADDRESS  адрес для клиента (по умолчанию ws://127.0.0.1:$ORCA_PORT)
#   HTTPS_PROXY           http://host:port — Maven и Gradle переменные окружения не читают,
#                         им прокси прописывается в ~/.m2/settings.xml и ~/.gradle/gradle.properties
#   GIT_AUTHOR_NAME/EMAIL автор коммитов, записывается и в user.name/user.email ~/.gitconfig
#   GIT_SIGN=0            не подписывать коммиты и теги (по умолчанию подпись включена)
#   GIT_SIGNING_KEY       SSH-ключ подписи (по умолчанию ~/.ssh/git-signing, создаётся при первом запуске)
#   GH_TOKEN              токен GitHub: git по https берёт его из окружения (в ~/.gitconfig не пишется)
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

# ---------------------------------------------------------------- git
# ~/.gitconfig — в томе agent-home; настройки ниже перезаписываются при каждом старте из .env
if [[ -n "${GIT_AUTHOR_NAME:-}" ]]; then git config --global user.name "$GIT_AUTHOR_NAME"; fi
if [[ -n "${GIT_AUTHOR_EMAIL:-}" ]]; then git config --global user.email "$GIT_AUTHOR_EMAIL"; fi

# GitHub по https с токеном из окружения: токен не попадает в файлы, смена токена — пересоздание контейнера
if [[ -n "${GH_TOKEN:-}" ]]; then
  git config --global credential.https://github.com.helper \
    '!f() { test "$1" = get && echo username=x-access-token && echo "password=$GH_TOKEN"; }; f'
fi

# Подпись коммитов и тегов SSH-ключом контейнера (отдельный ключ, не ключ хоста: его можно отозвать
# на GitHub, не трогая личный). Публичный ключ — добавить в GitHub как Signing key, тогда коммиты «Verified»
if [[ "${GIT_SIGN:-1}" != 0 ]]; then
  signing_key="${GIT_SIGNING_KEY:-$HOME/.ssh/git-signing}"
  if [[ ! -e "$signing_key" ]]; then
    mkdir -p "$(dirname "$signing_key")"
    chmod 700 "$(dirname "$signing_key")"
    ssh-keygen -q -t ed25519 -N '' -C "agent-box ${GIT_AUTHOR_EMAIL:-signing}" -f "$signing_key"
    echo "agent-entrypoint: создан ключ подписи git $signing_key.pub — добавить в GitHub: Settings → SSH and GPG keys → Signing key" >&2
  fi
  git config --global gpg.format ssh
  git config --global user.signingkey "$signing_key.pub"
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true
  # Проверка своих подписей (git log --show-signature)
  allowed_signers="$HOME/.ssh/allowed_signers"
  echo "${GIT_AUTHOR_EMAIL:-*} $(cat "$signing_key.pub")" >"$allowed_signers"
  git config --global gpg.ssh.allowedSignersFile "$allowed_signers"
else
  git config --global commit.gpgsign false
  git config --global tag.gpgsign false
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
