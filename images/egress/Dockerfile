# ================================================================ egress
# Выход agent в интернет: squid пропускает только домены из allowlist.txt, остальное — 403 и запись в лог.
# HTTPS не расшифровывается: домен берётся из CONNECT. Образ: localhost/agent-box-egress
#
# Конфиг в образ не входит: compose.yaml монтирует settings/egress/squid.conf и allowlist.txt
# в /etc/squid. После правки — перезапустить контейнер egress, пересборка не нужна.

ARG COMMON_IMAGE=localhost/agent-box/common:latest
FROM ${COMMON_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends squid \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /
USER proxy
EXPOSE 3128
# Ошибка в конфиге или списке останавливает запуск с сообщением squid, а не ломает работу молча
ENTRYPOINT ["/bin/sh", "-c", "squid -k parse -f /etc/squid/squid.conf && exec squid -N -f /etc/squid/squid.conf"]
