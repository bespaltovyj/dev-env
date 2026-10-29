# ================================================================ grafana
# Grafana с плагинами, установленными при сборке: в работе у Grafana нет выхода в интернет
# (сеть monitoring — internal). Образ: localhost/agent-box-grafana
#   victoriametrics-logs-datasource — источник данных VictoriaLogs;
#   Drilldown-приложения (включаются settings/monitoring/grafana/provisioning/plugins/apps.yaml):
#     grafana-metricsdrilldown-app — Metrics, работает с VictoriaMetrics (Prometheus API);
#     grafana-lokiexplore-app      — Logs, только для Loki;
#     grafana-exploretraces-app    — Traces, только для Tempo;
#     grafana-pyroscope-app        — Profiles, только для Pyroscope.
#
# Плагины не в /var/lib/grafana: туда монтируются данные Grafana и скрыли бы их.

ARG GRAFANA_IMAGE=docker.io/grafana/grafana:13.3.0
FROM ${GRAFANA_IMAGE}

ARG VICTORIALOGS_PLUGIN_VERSION=0.33.1
ARG METRICS_DRILLDOWN_VERSION=3.0.0
ARG LOGS_DRILLDOWN_VERSION=3.0.0
ARG TRACES_DRILLDOWN_VERSION=3.0.0
ARG PROFILES_DRILLDOWN_VERSION=3.0.0
ENV GF_PATHS_PLUGINS=/opt/grafana-plugins
USER root
RUN grafana cli --pluginsDir /opt/grafana-plugins plugins install victoriametrics-logs-datasource "${VICTORIALOGS_PLUGIN_VERSION}" \
 && grafana cli --pluginsDir /opt/grafana-plugins plugins install grafana-metricsdrilldown-app "${METRICS_DRILLDOWN_VERSION}" \
 && grafana cli --pluginsDir /opt/grafana-plugins plugins install grafana-lokiexplore-app "${LOGS_DRILLDOWN_VERSION}" \
 && grafana cli --pluginsDir /opt/grafana-plugins plugins install grafana-exploretraces-app "${TRACES_DRILLDOWN_VERSION}" \
 && grafana cli --pluginsDir /opt/grafana-plugins plugins install grafana-pyroscope-app "${PROFILES_DRILLDOWN_VERSION}" \
 && chown -R grafana:root /opt/grafana-plugins
USER grafana
