# ================================================================ egress
# Выход agent в интернет: squid пропускает только домены из allowlist.txt, остальное — 403 и запись в лог.
# HTTPS не расшифровывается: домен берётся из CONNECT. Образ: localhost/agent-box-egress
#
# allowlist.txt встроен в образ: после правки — .\build.ps1 и пересоздать сервис egress.

ARG DEBIAN_IMAGE=debian:trixie-slim
FROM ${DEBIAN_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends squid \
 && rm -rf /var/lib/apt/lists/*

COPY squid.conf    /etc/squid/squid.conf
COPY allowlist.txt /etc/squid/allowlist.txt

# Ошибка в конфиге или списке ломает сборку, а не запуск
RUN squid -k parse -f /etc/squid/squid.conf

USER proxy
EXPOSE 3128
ENTRYPOINT ["squid", "-N", "-f", "/etc/squid/squid.conf"]
