#!/bin/bash
# Дашборды Grafana по умолчанию (сервис grafana-dashboards, профиль monitoring).
# При старте профиля импортирует каждый /dashboards/<папка>/*.json через API в папку Grafana <папка>,
# только если дашборда с таким uid ещё нет. Дальше это обычный дашборд в базе Grafana: его можно менять
# и сохранять в UI, правки не перезаписываются. Чтобы снова взять версию из файла — удалить дашборд в
# Grafana и перезапустить сервис: podman start agent-box-grafana-dashboards-1.
#
# Не провижининг Grafana: провижининг с allowUiUpdates перезаписывает правки из UI при каждом старте Grafana.
set -uo pipefail

URL="${GRAFANA_URL:-http://grafana:3000}"
AUTH="${GRAFANA_USER:-admin}:${GRAFANA_PASSWORD:-admin}"
SRC=/dashboards

log() { echo "$(date '+%F %T') $*"; }

# Ждать Grafana (до 2 минут)
for _ in $(seq 1 60); do
  curl -sf "$URL/api/health" > /dev/null && break
  sleep 2
done
curl -sf "$URL/api/health" > /dev/null || { log "!! Grafana недоступна: $URL"; exit 1; }

for dir in "$SRC"/*/; do
  folder="$(basename "$dir")"
  # Папка: uid = имя папки; 409/412 — уже есть
  curl -s -o /dev/null -u "$AUTH" -H 'Content-Type: application/json' -X POST "$URL/api/folders" \
    --data "{\"uid\":\"$folder\",\"title\":\"$folder\"}"

  for file in "$dir"*.json; do
    [[ -e "$file" ]] || continue
    # overwrite:false — существующий дашборд (тот же uid или название в папке) не трогается:
    # Grafana отвечает 409 (уже есть) или 412 (изменён)
    code=$(
      { printf '{"overwrite":false,"folderUid":"%s","message":"импорт из settings","dashboard":' "$folder"
        cat "$file"
        printf '}'
      } | curl -s -o /tmp/response.json -w '%{http_code}' -u "$AUTH" -H 'Content-Type: application/json' \
            -X POST "$URL/api/dashboards/db" --data-binary @-
    )
    case "$code" in
      200) log "импортирован $folder/$(basename "$file")" ;;
      409|412) log "уже есть, не трогаю: $folder/$(basename "$file")" ;;
      *)   log "!! $folder/$(basename "$file"): HTTP $code $(cat /tmp/response.json)" ;;
    esac
  done
done
