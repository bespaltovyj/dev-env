# ================================================================ grafana
# Grafana с плагином VictoriaLogs, установленным при сборке: в работе у Grafana нет выхода в интернет
# (сеть monitoring — internal). Образ: localhost/agent-box-grafana
#
# Плагины не в /var/lib/grafana: туда монтируется data/monitoring/grafana и скрыл бы их.

ARG GRAFANA_IMAGE=docker.io/grafana/grafana:13.3.0
FROM ${GRAFANA_IMAGE}

ARG VICTORIALOGS_PLUGIN_VERSION=0.33.1
ENV GF_PATHS_PLUGINS=/opt/grafana-plugins
USER root
RUN grafana cli --pluginsDir /opt/grafana-plugins plugins install victoriametrics-logs-datasource "${VICTORIALOGS_PLUGIN_VERSION}" \
 && chown -R grafana:root /opt/grafana-plugins
USER grafana
