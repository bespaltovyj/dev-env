# agent-box: правила для Claude Code

## Дашборды Grafana

Grafana профиля monitoring: http://127.0.0.1:3000 (README.md, п. 10). Дашборды создаются и правятся через API
(`POST /api/dashboards/db` с `"overwrite": true`). Каждый дашборд, который создаётся или правится, должен
соответствовать правилам ниже; правка существующего дашборда — повод привести его к ним целиком.

### Переменные

- `datasource` — тип `datasource`, `query: "prometheus"`, по умолчанию VictoriaMetrics (uid `victoria-metrics`).
  Используется в каждой панели и в каждом запросе: `"datasource": { "type": "prometheus", "uid": "${datasource}" }`.
  Источник данных с фиксированным uid в панелях не указывать.
- `timeWindow` — тип `custom`, значения `1m,5m,30m,1h,1d`, по умолчанию `5m`, с возможностью ввести своё значение
  (`"allowCustomValue": true`).

### Запросы

- Окно функций по диапазону (`rate`, `increase`, `irate`, `*_over_time` и т. п.) — всегда `[$timeWindow]`,
  не `[$__rate_interval]`, `[$__interval]` и не фиксированное `[5m]`.
- У таких запросов «Min step» = `$timeWindow`: в JSON запроса `"interval": "$timeWindow"`.
- Выражения форматируются с отступами в 2 пробела: каждая функция и агрегация открывает новый уровень,
  селектор метрики — на отдельной строке. Метки селектора — каждая на своей строке с отступом на уровень глубже
  и запятой в конце (в том числе после последней); закрывающая `}` — на уровне имени метрики, окно `[...]` —
  сразу после неё.

  ```promql
  sum(
    rate(
      squid_client_http_requests_total{
        job="squid",
      }[$timeWindow]
    )
  )
  ```

- `refId` — понятное короткое имя по смыслу запроса латиницей (`requests`, `errors`, `traffic_in`, `p95`),
  а не сгенерированные `A`, `B`, `C`. Без лишних подробностей: `errors`, а не `client_http_errors_per_second_5m`.
