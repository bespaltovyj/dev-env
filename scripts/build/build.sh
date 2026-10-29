#!/usr/bin/env bash
# Сборка agent-box: common -> компоненты (параллельно) -> итоговый образ и Grafana.
#
#   ./scripts/build/build.sh                              # всё
#   ./scripts/build/build.sh --build-arg GO_VERSION=...   # аргументы передаются во все сборки
#   ENGINE=docker JOBS=8 ./scripts/build/build.sh
#
# Пути (images/, .build-logs) считаются от корня репозитория, текущая папка не важна.
#
# Переменные: ENGINE (podman), PREFIX (localhost/agent-box), IMAGE (localhost/agent-box:latest),
#             GRAFANA_IMAGE (localhost/agent-box-grafana:latest),
#             JOBS (4 параллельные сборки), LOG_DIR (.build-logs)
set -euo pipefail

# Корень репозитория: скрипт лежит в scripts/build
cd "$(dirname "$0")/../.."

ENGINE="${ENGINE:-podman}"
PREFIX="${PREFIX:-localhost/agent-box}"
IMAGE="${IMAGE:-localhost/agent-box:latest}"
GRAFANA_IMAGE="${GRAFANA_IMAGE:-localhost/agent-box-grafana:latest}"
JOBS="${JOBS:-4}"
LOG_DIR="${LOG_DIR:-.build-logs}"
EXTRA_ARGS=("$@")

# Волны: внутри волны компоненты собираются параллельно
WAVE1=(node jdk17 jdk21 jdk25 maven gradle go uv ruff kubectl helm orca dcg claude)
WAVE2=(pytest)   # зависит от uv

# Зависимости компонентов от других компонентов
declare -A DEPS=([pytest]="uv")

COMMON_ARGS=()
if [[ "$ENGINE" == podman ]]; then
  COMMON_ARGS+=(--format docker)
fi

mkdir -p "$LOG_DIR"

context_args() {
  local name
  for name in "$@"; do
    printf -- '--build-context\n%s=docker-image://%s/%s:latest\n' "$name" "$PREFIX" "$name"
  done
}

# images/<группа>/<name>.Dockerfile
stage_file() {
  local file
  file="$(find images -name "$1.Dockerfile" -print -quit)"
  [[ -n "$file" ]] || { echo "!! нет images/**/$1.Dockerfile" >&2; return 1; }
  echo "$file"
}

build_component() {
  local name="$1" deps=() file
  file="$(stage_file "$name")" || return 1
  [[ -n "${DEPS[$name]:-}" ]] && mapfile -t deps < <(context_args ${DEPS[$name]})
  # settings: статические настройки репозитория (common копирует settings/apt)
  "$ENGINE" build "${COMMON_ARGS[@]}" \
    --build-arg "COMMON_IMAGE=$PREFIX/common:latest" \
    --build-context settings=settings \
    "${deps[@]}" "${EXTRA_ARGS[@]}" \
    -t "$PREFIX/$name:latest" -f "$file" images \
    >"$LOG_DIR/$name.log" 2>&1
}

build_wave() {
  local name failed=()
  for name in "$@"; do
    while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n || true; done
    echo "  -> $name"
    # Код выхода пишется в файл: wait -n мог уже забрать статус процесса
    { if build_component "$name"; then echo 0; else echo 1; fi; } >"$LOG_DIR/$name.rc" &
  done
  wait
  for name in "$@"; do
    [[ "$(cat "$LOG_DIR/$name.rc")" == 0 ]] || failed+=("$name")
  done
  if (( ${#failed[@]} )); then
    for name in "${failed[@]}"; do
      echo "!! $name: ошибка сборки, лог $LOG_DIR/$name.log" >&2
      tail -n 20 "$LOG_DIR/$name.log" >&2
    done
    exit 1
  fi
}

echo "== common"
build_component common || { tail -n 20 "$LOG_DIR/common.log" >&2; exit 1; }

echo "== компоненты"
build_wave "${WAVE1[@]}"
build_wave "${WAVE2[@]}"

echo "== $IMAGE"
mapfile -t FINAL_CONTEXTS < <(context_args "${WAVE1[@]}" "${WAVE2[@]}")
"$ENGINE" build "${COMMON_ARGS[@]}" "${FINAL_CONTEXTS[@]}" "${EXTRA_ARGS[@]}" \
  --build-arg "COMMON_IMAGE=$PREFIX/common:latest" \
  -t "$IMAGE" -f images/Dockerfile . 2>&1 | tee "$LOG_DIR/final.log"

# Grafana для профиля monitoring: плагины ставятся при сборке. Egress (Envoy) — готовый образ, не собирается
echo "== $GRAFANA_IMAGE"
"$ENGINE" build "${COMMON_ARGS[@]}" -t "$GRAFANA_IMAGE" -f images/monitoring/grafana.Dockerfile images/monitoring \
  >"$LOG_DIR/grafana.log" 2>&1 || { tail -n 20 "$LOG_DIR/grafana.log" >&2; exit 1; }

echo "== готово: $IMAGE, $GRAFANA_IMAGE"
