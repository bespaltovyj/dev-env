# agent-box: сведения о проекте для ИИ-агентов

Краткий обзор для агента, работающего в этом репозитории. Архитектура и быстрый старт — README.md,
детальное описание и разбор проблем — FAQ.md, инструкции агентам внутри контейнера — `settings/ai/AGENTS.md`.

## Что это

Изолированное окружение для ИИ-агентов на Windows: Podman-машина `agents` (Fedora CoreOS в Hyper-V)
и контейнеры: `agent` (рабочий; интернет — только через прокси-egress), `egress` (Envoy с allowlist
доменов), `postgres` (PostgreSQL 18), профили `monitoring` (VictoriaMetrics/Logs/Traces, Grafana,
otel-collector) и `backup`. Десктопный Orca на Windows подключается к `orca-ide serve` в контейнере
agent через gvproxy/hvsock (порт 6769 на 127.0.0.1).

## Ключевые инварианты

- Контейнер agent выходит в интернет только через прокси egress с allowlist доменов
  (`settings/egress/envoy.yaml`; порты 80/443, HTTPS не расшифровывается). Новый внешний домен =
  новая строка в allowlist + `podman restart agent-box-egress-1`. Отказы видны в
  `podman logs agent-box-egress-1` (`rbac_access_denied`).
- Изменяемые данные — только в named volume на диске VM (`compose-win.yaml`). Папки Windows, подключённые
  по 9p, не хранят владельца, права и блокировки — на них падают git, Orca и PostgreSQL (FAQ.md, п. 2).
  `compose-unix.yaml` — вариант для Linux/macOS с данными в `./data` на хосте.
- Сборка — `scripts/build/build.ps1` / `build.sh`: `common` → компоненты `images/<группа>/<name>.Dockerfile`
  (параллельно, волны) → итоговый `images/Dockerfile`. Сборке нужна запущенная машина, но не права
  администратора; `podman compose`, наоборот, требует администратора (Hyper-V).
- Версии инструментов фиксируются ARG в Dockerfiles (`NODE_VERSION`, `KIMI_VERSION`, ...); автообновления
  внутри контейнера выключены (`DISABLE_AUTOUPDATER`, `KIMI_CODE_NO_AUTO_UPDATE`).
- `settings/` — только статика, безопасная для git; секреты — в `.env` (не в git).
- Работа в контейнере — через tmux: сессия `orca` держит `orca-ide serve`, работа идёт в сессии `main`
  (`podman compose -f compose-win.yaml exec agent tmux new -A -s main`).
- Агенты в контейнере: Claude Code (`claude`) и Kimi Code CLI (`kimi`, конфиг в `~/.kimi-code`, том `kimi`).
  Единые инструкции им — `settings/ai/AGENTS.md`, смонтированный в `~/.claude` и `~/.kimi-code` (только чтение).

## Структура

- `compose-win.yaml`, `compose-unix.yaml` — два варианта запуска одного набора сервисов.
- `FAQ.md` — детальное описание (создание машины, тома и копии, egress, Orca, мониторинг, PostgreSQL) и разбор проблем.
- `images/` — Dockerfile'ы: `common/common.Dockerfile` (база: Debian + curl), `ai/` (orca, claude, kimi,
  dcg), `js`, `jvm`, `python`, `go`, `k8s`, `monitoring` (Grafana), итоговый `Dockerfile` собирает всё
  через `--build-context` из образов компонентов.
- `scripts/build/` — `build.ps1`/`build.sh` (волны сборки), `entrypoint.sh` (прокси для Maven/Gradle,
  git-подпись SSH-ключом контейнера, tmux-сессия orca), `langfuse_hook.py` (трейсы Claude Code в Langfuse,
  хук Stop из управляемых настроек).
- `settings/ai/` — `AGENTS.md` (единые инструкции агентам) и `CLAUDE.md` (ссылка на него через `@import`).
- `settings/egress/envoy.yaml` — allowlist egress; `settings/managed-settings.json` — управляемые настройки
  Claude Code (хуки dcg и Langfuse, без телеметрии); `settings/monitoring/` — otel-collector, otel-agent,
  vmauth, Grafana (provisioning, дашборды по умолчанию); `settings/backup/backup.sh` — копии томов раз в час.
- `data/backup/` — не в git: резервные копии томов (профиль `backup` по умолчанию выключен).

## Команды

```bat
.\scripts\build\build.ps1                                     :: сборка всех образов (без админа, машина запущена)
sudo podman compose -f compose-win.yaml up -d --force-recreate  :: применить новый образ / .env (админ)
podman compose -f compose-win.yaml exec agent tmux new -A -s main  :: работа в контейнере (без админа)
podman restart agent-box-egress-1                               :: после правки allowlist
podman logs agent-box-egress-1 | findstr rbac_access_denied     :: чего не хватает в списке доменов
```

## Конвенции документации

README.md — архитектура и быстрый старт; FAQ.md — основная документация, ведётся на русском; всё, что видно
в UI Grafana (дашборды, панели, легенды), — только на английском (правила оформления — в `settings/ai/AGENTS.md`).
Изменения схемы томов, сборки или сети требуют синхронных правок README/FAQ.md и, при необходимости,
`settings/ai/AGENTS.md`.
