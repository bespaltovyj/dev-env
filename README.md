# agent-box: изолированное окружение для ИИ-агентов на Windows (Podman + Hyper-V)

## Архитектура

```
┌── host ──────────────────────────────────────────────────┐              ┌── Hyper-V VM «agents»: Fedora CoreOS ──────────────────────┐
│                                                          │              │  vsock-network.service → tap0 192.168.127.2                │
│ ┌── gvproxy.exe ───────────────────────────────────────┐ │              │  settings:ro ◄─ 9p ◄─ A:\orca\docker\settings              │
│ │ 127.0.0.1:52230  SSH  ───────────────────────────────┼─┼───────────►  │  sshd :22 (podman API, rootless, core)                     │
│ │                                                      │ │              │  data ◄─ 9p ◄─ A:\orca\docker\data (backup)                │
│ │ 127.0.0.1:6769   orca ───────────────────────────────┼─┼───────────►  │  127.0.0.1:6769 → orca-ide serve (ниже)                    │
│ └────────────▲───────────────────────────▲─────────────┘ │              │ ┌── контейнер agent-box-agent-1 ─────────────────────────┐ │
│         ws :6769                  ssh :52230             │              │ │ cap_drop ALL · no-new-privileges                       │ │
│                                                          │              │ │ сеть agent-internal: без выхода наружу и DNS           │ │
│ ┌── Orca.exe ─────────────┐ ┌── podman.exe ────────────┐ │              │ │ PID 1 tini                                             │ │
│ │ десктоп · окно          │ │ build/run/exec           │ │              │ │ └─ agent-entrypoint (entrypoint.sh)                    │ │
│ │ свой рантайм :6768      │ │ — пользователь           │ │              │ │    ├─ sleep infinity — держит контейнер                │ │
│ │ (занят)                 │ │ machine/compose          │ │              │ │    └─ tmux new -d -s orca                              │ │
│ └─────────────────────────┘ │ — администратор          │ │              │ │ tmux «orca»: orca-ide serve :6769                      │ │
│                             └──────────────────────────┘ │              │ │   └─ orcad-server → терминалы и агенты                 │ │
│                                                          │              │ │ tmux «main»: bash · claude · kimi · codex ·           │ │
│                                                          │              │ │   gemini · qwen · opencode · java · mvn · gradle · go  │ │
│ ┌── порты на 127.0.0.1 (compose → контейнеры) ─────────┐ │              │ │ /repos · ~/.claude · ~/.kimi-code · ~/.config/orca     │ │
│ │ 6769 → agent: orca-ide serve                         │ │              │ │   ~/.orca · ~/.local/state/bash …                      │ │
│ │ 5432 → postgres: PostgreSQL 18                       │ │              │ │ ◄─ named volumes на диске VM (кэши — отдельные тома)   │ │
│ │ 9902 → egress: /stats/prometheus                     │ │              │ └────────────────────────────────────────────────────────┘ │
│ │ 3000 → grafana · 8427 → vmauth (VMUI)                │ │              │   HTTP(S)_PROXY ──────────► egress :3128                   │
│ │ 8428 → victoria-metrics · 9428 → victoria-logs       │ │              │ ┌── egress (Envoy) ─────────┐   ┌── internet ────────────┐ │
│ │ 10428 → victoria-traces · 8080 → cadvisor            │ │              │ │ :3128 HTTP(S) прокси      │   │ только из списка       │ │
│ │ 4317/4318 → otel OTLP · 9090 → remote write          │ │              │ │ allowlist (envoy.yaml)    │   │ github · npm · pypi    │ │
│ │ 8888 → otel: свои метрики                            │ │              │ │ иначе → 403 + журнал      │──►│ anthropic · maven      │ │
│ │ 52230* → gvproxy: SSH/podman API (* — при init)      │ │              │ │ сети: agent-internal +    │   │ moonshot · langfuse    │ │
│ │ 3000–10428, 4317/4318, 9090, 8888: профиль monitoring│ │              │ │ outside → интернет        │   │ через gvproxy          │ │
│ └──────────────────────────────────────────────────────┘ │              │ └───────────────────────────┘   └────────────────────────┘ │
│                                                          │              │                                                            │
│                                                          │              │  Все порты публикуются только на 127.0.0.1 хоста           │
└──────────────────────────────────────────────────────────┘              └────────────────────────────────────────────────────────────┘
```

Orca на хосте подключается к `orca-ide serve` в контейнере:
`Orca.exe → ws://127.0.0.1:6769 → gvproxy.exe → hvsock → VM → контейнер :6769 → orca-ide serve (tmux «orca»)`.
Порт 6768 занят собственным рантаймом десктопного Orca; 52230 — пример SSH-порта в VM для `podman.exe`
(назначается при `podman machine init`, см. FAQ.md, п. 3). Весь трафик хост ↔ VM идёт через gvproxy:
без него не работают ни 6769, ни SSH. Выход контейнера agent в интернет — только через прокси egress
со списком доменов (FAQ.md, п. 8).

Данные контейнеров — в named volume на диске VM (с Windows не видны, удаляются вместе с машиной):
`repos`, `orca-worktrees`, `claude`, `kimi`, `codex`, `gemini`, `qwen`, `orca-config`, `orca-home`,
`bash-history`, `postgres`, `victoria-metrics`, `victoria-logs`, `victoria-traces`, `grafana`;
кэши — `agent-home`, `orcad-artifacts`.
Копии томов: сервис `backup` и ручной export — FAQ.md «Резервная копия томов».

Агентские CLI в контейнере (логин — интерактивно в tmux, конфиги — в named volume):

| CLI | Провайдер | Конфиг (том) | Аутентификация |
|---|---|---|---|
| `claude` | Anthropic | `~/.claude` (`claude`) | подписка Pro/Max или API-ключ |
| `kimi` | Moonshot AI | `~/.kimi-code` (`kimi`) | OAuth или API-ключ Kimi Platform |
| `codex` | OpenAI | `~/.codex` (`codex`) | ChatGPT-аккаунт или `OPENAI_API_KEY` |
| `gemini` | Google | `~/.gemini` (`gemini`) | Google-аккаунт или `GEMINI_API_KEY` |
| `qwen` | Alibaba | `~/.qwen` (`qwen`) | Qwen-аккаунт или `DASHSCOPE_API_KEY` |
| `opencode` | любой (провайдеры на выбор) | `~/.local/share/opencode` (`opencode`) | `opencode auth` или API-ключи провайдеров |

## Структура репозитория

```
compose-win.yaml                    запуск на Windows (Podman + Hyper-V): данные в named volume (FAQ.md, п. 6)
compose-unix.yaml                   запуск на Linux/macOS: данные в data/ (FAQ.md «Linux и macOS»)
.env.example                        переменные для compose (FAQ.md, п. 6)
FAQ.md                              детальное описание и разбор проблем
AGENTS.md                           обзор проекта для ИИ-агентов (в корне репозитория)
settings/                           только статические настройки, безопасные для git
├── apt/debian.sources              источники apt (только https), встраивается в образ common
├── ai/AGENTS.md, CLAUDE.md         инструкции агентам: единый AGENTS.md (CLAUDE.md ссылается на него),
                                    монтируются в ~/.claude и ~/.kimi-code только для чтения
├── managed-settings.json           управляемые настройки Claude Code (хуки dcg и Langfuse, без телеметрии) — монтируется в /etc/claude-code только для чтения
├── opencode/opencode.json          управляемые настройки opencode (autoupdate выключен) — монтируется в /etc/opencode только для чтения
├── egress/envoy.yaml               конфиг egress (Envoy) с allowlist доменов — монтируется в egress (FAQ.md, п. 8)
├── backup/backup.sh                скрипт сервиса backup: копии томов раз в час (FAQ.md «Резервная копия томов»)
└── monitoring/                     otel-collector, otel-agent, vmauth; Grafana: источники, плагины, дашборды (FAQ.md, п. 10)
data/backup/                        не в git: резервные копии томов, сервис backup, профиль backup (FAQ.md «Резервная копия томов»).
                                    Сами данные контейнеров — в named volume на диске VM (FAQ.md, п. 6)
images/
├── Dockerfile                      итоговый образ localhost/agent-box
├── common/common.Dockerfile        базовый образ: Debian, apt по https, curl (на нём собираются все)
├── ai/ go/ js/ jvm/ k8s/ python/   компоненты: <группа>/<name>.Dockerfile
└── monitoring/grafana.Dockerfile   Grafana с плагинами VictoriaLogs и Drilldown (FAQ.md, п. 10)
scripts/build/
├── build.ps1, build.sh             сборка всех образов (FAQ.md, п. 5)
└── entrypoint.sh                   точка входа контейнера agent
```

## Быстрый старт

Все команды по порядку, подробности — в FAQ.md. Путь к проекту задаётся один раз в переменной
окружения `AGENT_BOX_DIR` (только для текущего окна консоли), остальные пути строятся от неё.
Номер шага перед командой не вводить. Блоки для cmd и PowerShell не смешивать: в приглашении cmd — `C:\...>`,
в PowerShell — `PS C:\...>` (из PowerShell в cmd можно перейти командой `cmd`, обратно — `exit`).

**Windows (PowerShell в режиме администратора)**

```powershell
1.  $env:AGENT_BOX_DIR = 'A:\orca\docker'   # общий путь к проекту (только для этого окна)
2.  $env:VM_DIR = '/mnt/a/orca/docker'   # тот же путь внутри VM: буква диска строчная, косые черты прямые
3.  Set-Location $env:AGENT_BOX_DIR   # перейти в папку проекта
4.  Set-ExecutionPolicy -Scope Process RemoteSigned   # активируем возможность выполнять скрипты (только для этого окна)
5.  New-Item -ItemType Directory -Force data | Out-Null   # папка data должна существовать до init
6.  podman machine init agents --provider hyperv --cpus 6 --memory 8192 --swap 0 --disk-size 100 -v "$env:AGENT_BOX_DIR\settings:$env:VM_DIR/settings:ro" -v "$env:AGENT_BOX_DIR\data:$env:VM_DIR/data"   # создание машины (FAQ.md, п. 2)
7.  Set-VM -Name agents -AutomaticStartAction Nothing   # VM не стартует сама при загрузке Windows (FAQ.md, п. 2)
8.  podman machine start agents   # запуск машины
9.  .\scripts\build\build.ps1   # сборка образов
10. Copy-Item .env.example .env   # инициализация env переменных для контейнеров (заполнить POSTGRES_PASSWORD, ключи)
11. podman compose -f "$env:AGENT_BOX_DIR\compose-win.yaml" --profile monitoring up -d --force-recreate   # запуск контейнеров (мониторинг: --profile monitoring)
12. podman exec -it agent-box-agent-1 tmux attach -t orca   # подключение к orca serve для копирования кода orca://pair?code=...
13. Ctrl+B, затем d   # выход из tmux-сессии; код добавить в десктопном Orca как удалённое окружение
```


**Linux / macOS**

```bash
1.  Открыть терминал   # права root не нужны: rootless podman
2.  export AGENT_BOX_DIR=~/orca/docker   # общий путь к проекту (только для этого терминала)
3.  cd "$AGENT_BOX_DIR"   # перейти в папку проекта
4.  podman machine init --cpus 6 --memory 8192 --disk-size 100 -v "$AGENT_BOX_DIR:$AGENT_BOX_DIR"   # только macOS: создание машины, папка проекта видна VM
5.  podman machine start   # только macOS: запуск машины
6.  mkdir -p data/{repos,orca-worktrees,claude,kimi,orca/config,orca/home,bash,postgres}   # папки для данных контейнеров (мониторинг — ещё data/monitoring/*)
7.  ./scripts/build/build.sh   # сборка образов
8.  cp .env.example .env   # инициализация env переменных для контейнеров (заполнить POSTGRES_PASSWORD, ключи)
9.  podman compose -f "$AGENT_BOX_DIR/compose-unix.yaml" up -d --force-recreate   # запуск контейнеров (мониторинг: --profile monitoring)
10. podman exec -it agent-box-agent-1 tmux attach -t orca   # подключение к orca serve для копирования кода orca://pair?code=...
11. Ctrl+B, затем d   # выход из tmux-сессии; код добавить в десктопном Orca как удалённое окружение
```

Код сопряжения новый при каждом запуске сервера. Если `orca serve` не запущен (`ORCA_SERVE=0` в `.env` или упал):

```bat
podman exec agent-box-agent-1 tmux kill-session -t orca
podman exec agent-box-agent-1 tmux new -d -s orca "orca-ide serve --port 6769 --pairing-address ws://127.0.0.1:6769"
```

**Каждый следующий раз** на Windows — от имени администратора: `podman machine start agents`, затем
`podman compose -f A:\orca\docker\compose-win.yaml up -d`.

## Полезное

1. Agentic Design Patterns - https://mokevnin.github.io/agentic-coding-design-patterns/ru/
2. https://martinfowler.com/articles/structured-prompt-driven/
