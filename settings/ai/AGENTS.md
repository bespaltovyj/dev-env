# Окружение agent-box

## Git-репозитории
- Все git-репозитории клонировать только в `/repos/<имя-репозитория>` (`$REPOS_DIR`), например
  `git clone https://github.com/org/app.git /repos/app`. Не клонировать в домашнюю папку, `/tmp` и другие места.
- `/repos` — постоянное хранилище: переживает пересоздание контейнера. Остальное вне `/repos` и домашней папки пропадёт.

## PostgreSQL
- PostgreSQL 18 доступен по адресу `postgres:5432`; пользователь, пароль и БД по умолчанию — в переменных
  `$POSTGRES_USER`, `$POSTGRES_PASSWORD`, `$POSTGRES_DB`. Для своих задач создавать отдельные базы
  (`createdb -h postgres -U "$POSTGRES_USER" <имя>`), а не писать в базу по умолчанию.

## Сеть
- Интернет только через прокси с allowlist: доступны GitHub (только https, не ssh), реестры npm, PyPI, Go,
  Maven Central, Gradle, Kubernetes/Helm, Anthropic и Kimi/Moonshot (api.kimi.com, api.kimi.ai,
  api.moonshot.cn, api.moonshot.ai, auth.kimi.com). Ответ 403 от прокси — домена нет в списке, обходить не пытаться.

## Kimi Code CLI
- Конфиг, логин, сессии и история CLI — в `~/.kimi-code` (том `kimi`): переживают пересоздание контейнера.
- Автообновление отключено в образе (`KIMI_CODE_NO_AUTO_UPDATE=1`): версия фиксируется образом и меняется
  только пересборкой. `kimi upgrade` не запускать.

## Дашборды Grafana

Grafana профиля monitoring: из контейнера — `http://grafana:3000`, с хоста — http://127.0.0.1:3000 (FAQ.md,
п. 10). Логин и пароль — `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD` из `.env`. Дашборды создаются и правятся
через API (`POST /api/dashboards/db` с `"overwrite": true`). Каждый дашборд, который создаётся или правится,
должен соответствовать правилам ниже; правка существующего дашборда — повод привести его к ним целиком.

Дашборды по умолчанию — JSON-модели (объект `dashboard`, без `id`, с постоянным `uid`) в
`settings/monitoring/grafana/dashboards/<папка>/<имя>.json`; сервис `grafana-dashboards` импортирует их, только если
дашборда с таким uid в Grafana ещё нет. После создания или правки дашборда через API обновить и его файл, иначе
при новой установке появится старая версия.

### Язык

Всё, что видно в Grafana, — только на английском: названия дашбордов, панелей и строк (row), описания,
подписи переменных (`label`), легенды (`legendFormat`), переименования колонок и значений. Русский — только в
комментариях этих правил и в документации репозитория.

### Переменные

- `datasource` — тип `datasource`, `query: "prometheus"`, по умолчанию VictoriaMetrics (uid `victoria-metrics`).
  Используется в каждой панели и в каждом запросе: `"datasource": { "type": "prometheus", "uid": "${datasource}" }`.
  Источник данных с фиксированным uid в панелях не указывать.
- `timeWindow` — тип `custom`, значения `1m,5m,30m,1h,1d`, по умолчанию `5m`, с возможностью ввести своё значение
  (`"allowCustomValue": true`).
- Панели на логах — отдельная переменная `logs_datasource` (тип `datasource`, `query: "victoriametrics-logs-datasource"`,
  по умолчанию VictoriaLogs, uid `victoria-logs`); для них `datasource` не используется.

### Запросы

- Окно функций по диапазону (`rate`, `increase`, `irate`, `*_over_time` и т. п.) — всегда `[$timeWindow]`,
  не `[$__rate_interval]`, `[$__interval]` и не фиксированное `[5m]`.
- У таких запросов «Min step» = `$timeWindow`: в JSON запроса `"interval": "$timeWindow"`.
- Исключение — итоги за весь интервал дашборда (таблицы «… за интервал», instant-запросы): окно `[$__range]`,
  без Min step.
- Выражения форматируются с отступами в 2 пробела: каждая функция и агрегация открывает новый уровень,
  селектор метрики — на отдельной строке. Метки селектора — каждая на своей строке с отступом на уровень глубже
  и запятой в конце (в том числе после последней); закрывающая `}` — на уровне имени метрики, окно `[...]` —
  сразу после неё.

  ```promql
  sum(
    rate(
      envoy_http_downstream_rq_total{
        job="envoy",
        envoy_http_conn_manager_prefix="egress",
      }[$timeWindow]
    )
  ) > 0
  ```

- Каждое PromQL-выражение заканчивается фильтром `> 0` — после закрывающей скобки внешней функции, на той же
  строке (`) > 0`): нулевые серии не попадают на графики, в легенду и таблицы. Плиткам (stat) при этом —
  `"noValue": "0"`, чтобы вместо «No data» показывался 0. Выражения Math (`$x * 0`) фильтр не получают.
- `refId` — понятное короткое имя по смыслу запроса латиницей (`requests`, `errors`, `traffic_in`, `p95`),
  а не сгенерированные `A`, `B`, `C`. Без лишних подробностей: `errors`, а не `client_http_errors_per_second_5m`.
- Запросы LogsQL (VictoriaLogs) — фильтр на первой строке, каждый `| pipe` на своей строке.

### Графики (timeseries)

- Tooltip — режим All: `"tooltip": { "mode": "multi", "sort": "desc" }`.
- Легенда — таблица внизу: `"legend": { "displayMode": "table", "placement": "bottom", "calcs": [...] }`.
  Значения в легенде:
  - `rate` (и всё, что из него считается: `histogram_quantile` по `rate`), а также текущие значения (gauge) —
    `["min", "max", "mean", "median", "lastNotNull"]` (в UI: Min, Max, Mean, Median, Last *);
  - `increase` и подсчёты за интервал (например, `stats ... count()` в LogsQL) — `["sum"]` (Total).
- Трафик в обе стороны (network: отправлено/получено) — на одном графике:
  - легенда начинается со стрелки: `↑ {{host}}` — отправлено, `↓ {{host}}` — получено;
  - получено — ниже горизонтали: переопределение по префиксу строки `byRegexp` `^↓.*` →
    `custom.transform: "negative-Y"` (сам запрос без минуса);
  - пунктирная линия нуля — выражение Math (`"datasource": { "type": "__expr__", "uid": "__expr__" }`,
    `"type": "math"`, `"expression": "$<refId> * 0"`) от одного из запросов, обычно скрытой суммы
    (`"hide": true`), чтобы линия была одна; переопределение `byFrameRefID` → `custom.lineStyle` dash,
    цвет `text`, скрыть из легенды и tooltip.
