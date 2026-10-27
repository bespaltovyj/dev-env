#!/usr/bin/env bash
# Сборка agent-box: downloader -> компоненты (параллельно) -> итоговый образ.
#
#   ./build.sh                              # всё
#   ./build.sh --build-arg GO_VERSION=...   # аргументы передаются во все сборки
#   ENGINE=docker JOBS=8 ./build.sh
#
# Переменные: ENGINE (podman), PREFIX (localhost/agent-box), IMAGE (localhost/agent-box:latest),
#             EGRESS_IMAGE (localhost/agent-box-egress:latest), JOBS (4 параллельные сборки), LOG_DIR (.build-logs)
set -euo pipefail

cd "$(dirname "$0")"

ENGINE="${ENGINE:-podman}"
PREFIX="${PREFIX:-localhost/agent-box}"
IMAGE="${IMAGE:-localhost/agent-box:latest}"
EGRESS_IMAGE="${EGRESS_IMAGE:-localhost/agent-box-egress:latest}"
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

# stages/<группа>/<name>.Dockerfile или stages/<name>.Dockerfile
stage_file() {
  local file
  file="$(find stages -name "$1.Dockerfile" -print -quit)"
  [[ -n "$file" ]] || { echo "!! нет stages/**/$1.Dockerfile" >&2; return 1; }
  echo "$file"
}

build_component() {
  local name="$1" deps=() file
  file="$(stage_file "$name")" || return 1
  [[ -n "${DEPS[$name]:-}" ]] && mapfile -t deps < <(context_args ${DEPS[$name]})
  "$ENGINE" build "${COMMON_ARGS[@]}" \
    --build-arg "DOWNLOADER_IMAGE=$PREFIX/downloader:latest" \
    "${deps[@]}" "${EXTRA_ARGS[@]}" \
    -t "$PREFIX/$name:latest" -f "$file" stages \
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

echo "== downloader"
build_component downloader || { tail -n 20 "$LOG_DIR/downloader.log" >&2; exit 1; }

echo "== компоненты"
build_wave "${WAVE1[@]}"
build_wave "${WAVE2[@]}"

echo "== $IMAGE"
mapfile -t FINAL_CONTEXTS < <(context_args "${WAVE1[@]}" "${WAVE2[@]}")
"$ENGINE" build "${COMMON_ARGS[@]}" "${FINAL_CONTEXTS[@]}" "${EXTRA_ARGS[@]}" \
  -t "$IMAGE" -f Dockerfile . 2>&1 | tee "$LOG_DIR/final.log"

# Прокси для выхода agent в интернет (allowlist.txt встроен в образ)
echo "== $EGRESS_IMAGE"
"$ENGINE" build "${COMMON_ARGS[@]}" -t "$EGRESS_IMAGE" -f egress/Dockerfile egress \
  >"$LOG_DIR/egress.log" 2>&1 || { tail -n 20 "$LOG_DIR/egress.log" >&2; exit 1; }

echo "== готово: $IMAGE, $EGRESS_IMAGE"
