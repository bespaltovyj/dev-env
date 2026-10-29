#!/bin/bash
# Резервная копия томов agent-box (сервис backup в compose.yaml).
# Раз в BACKUP_INTERVAL секунд: дамп PostgreSQL и отпечаток файлов томов; если с прошлой копии ничего
# не изменилось — пропуск, иначе новая копия <дата-время>/ с <том>.tar и postgres.sql. Хранятся
# последние BACKUP_KEEP копий. Тома подключены только для чтения в /volumes/<том>, копии — в /backup
# (data/backup на Windows). Учитываются только папки вида <дата-время>: остальное в data/backup
# (например, ручная копия manual) не трогается.
#
# На 9p не переименовываются папки, поэтому готовая копия помечается файлом COMPLETE, а не переносом папки.
set -uo pipefail

SRC=/volumes
DEST=/backup
INTERVAL="${BACKUP_INTERVAL:-3600}"
KEEP="${BACKUP_KEEP:-2}"

log() { echo "$(date '+%F %T') $*"; }

# Готовые копии по возрастанию даты
complete_backups() {
  local d
  for d in "$DEST"/[0-9]*-[0-9]*/; do
    [[ -f "$d/COMPLETE" ]] && echo "${d%/}"
  done | sort
}

# Отпечаток данных: путь, размер, время изменения и права каждого файла + хэш дампа PostgreSQL.
# \restrict / \unrestrict pg_dumpall пишет со случайным ключом в каждый дамп — в отпечаток не входят
fingerprint() {
  { find "$SRC" -printf '%P\t%s\t%T@\t%m\n' | LC_ALL=C sort
    grep -Ev '^\\(un)?restrict ' /tmp/postgres.sql | sha256sum
  } | sha256sum | cut -d' ' -f1
}

rotate() {
  local d i backups
  mapfile -t backups < <(complete_backups)
  for (( i = 0; i < ${#backups[@]} - KEEP; i++ )); do
    rm -r "${backups[i]}" && log "удалена старая копия ${backups[i]}"
  done
  # Незавершённые копии остаются только после сбоя
  for d in "$DEST"/[0-9]*-[0-9]*/; do
    if [[ -d "$d" && ! -f "$d/COMPLETE" ]]; then
      rm -r "$d" && log "удалена незавершённая копия ${d%/}"
    fi
  done
  return 0
}

backup_once() {
  local fp last dir v name rc
  if ! pg_dumpall -h postgres -U "$POSTGRES_USER" --clean > /tmp/postgres.sql 2> /tmp/pg_dumpall.err; then
    log "!! pg_dumpall: $(cat /tmp/pg_dumpall.err)"
    return 1
  fi

  fp="$(fingerprint)"
  last="$(complete_backups | tail -n 1)"
  if [[ -n "$last" && "$(cat "$last/fingerprint" 2>/dev/null)" == "$fp" ]]; then
    log "без изменений, последняя копия $last"
    return 0
  fi

  dir="$DEST/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  for v in "$SRC"/*/; do
    name="$(basename "$v")"
    # Код 1 у GNU tar — файл изменился во время чтения (SQLite в работе): копия есть, это предупреждение
    tar -C "$v" -cf "$dir/$name.tar.part" .
    rc=$?
    if (( rc > 1 )); then
      log "!! tar $name: код $rc"
      return 1
    fi
    mv "$dir/$name.tar.part" "$dir/$name.tar"
  done
  cp /tmp/postgres.sql "$dir/postgres.sql"
  echo "$fp" > "$dir/fingerprint"
  touch "$dir/COMPLETE"
  log "копия $dir"
  rotate
}

trap 'exit 0' TERM INT
mkdir -p "$DEST"
log "старт: интервал ${INTERVAL} с, хранить ${KEEP} копии, тома: $(ls "$SRC" | tr '\n' ' ')"
while true; do
  backup_once || log "!! копия не создана, повтор через ${INTERVAL} с"
  sleep "$INTERVAL" &
  wait $!
done
