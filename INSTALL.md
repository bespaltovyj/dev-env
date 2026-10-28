# Установка agent-box на Windows (Podman + Hyper-V)

## Требования

- Windows 10/11 Pro или Enterprise с включённым Hyper-V
- Установленный Podman (CLI), при желании Podman Desktop
- Для работы с Orca — десктопный Orca на Windows

## Структура репозитория

```
compose.yaml, .env.example          запуск (п. 6)
settings/                           только статические настройки, безопасные для git
├── claude/CLAUDE.md                инструкции агентам, монтируется в ~/.claude/CLAUDE.md только для чтения
├── managed-settings.json           управляемые настройки Claude Code (хук dcg), встраивается в образ
├── egress/                         squid.conf, allowlist.txt — монтируются в egress (п. 8)
└── monitoring/                     otel-collector, otel-agent, vmauth, provisioning Grafana (п. 10)
data/                               не в git: изменяемые данные контейнера (п. 6)
├── claude/                         ~/.claude: логин, сессии, история, settings.json Claude Code
├── repos/                          /repos — git-репозитории всех агентов, repos/orca-worktrees — worktree Orca
├── orca/config/, orca/home/        ~/.config/orca, ~/.orca
├── bash/                           история bash (HISTFILE)
├── postgres/                       данные PostgreSQL 18 (п. 11)
└── monitoring/                     данные VictoriaMetrics, VictoriaLogs, VictoriaTraces, Grafana (п. 10)
images/
├── Dockerfile                      итоговый образ localhost/agent-box
├── common/downloader.Dockerfile    базовый образ для скачивания компонентов
├── ai/ go/ js/ jvm/ k8s/ python/   компоненты: <группа>/<name>.Dockerfile
├── egress/                         образ прокси (squid без конфига)
└── monitoring/grafana.Dockerfile   Grafana с плагином VictoriaLogs (п. 10)
scripts/build/
├── build.ps1, build.sh             сборка всех образов (п. 5)
└── entrypoint.sh                   точка входа контейнера agent
```

## Архитектура

```
┌── host ─────────────────────────────────────────────────────┐          ┌── Hyper-V VM «agents»: Fedora CoreOS ────────────────────────┐
│                                                             │          │                                                              │
│ ┌─ gvproxy.exe ───────────────────────────────────────────┐ │          │ vsock-network.service → tap0 192.168.127.2                   │
│ │ 127.0.0.1:52230  SSH ───────────────────────────────────┼─┼─ hvsock ─► sshd :22  (podman API, rootless, core)                       │
│ │ hvsock 0000DD87-… — сеть VM                             │ │          │ /mnt/a/orca/docker  ◄─ 9p ◄─ A:\podman (хост)                │
│ │                                                         │ │          │                                                              │
│ │ 1. sudo podman machine start                            │ │          │                                                              │
│ │ 2. .\scripts\build\build.ps1 или build.sh               │ │          │ ┌─ контейнер agent-box-agent-1 ────────────────────────────┐ │
│ │ 3. podman compose -f compose.yaml up -d --force-recreate│ │          │ │ cap_drop ALL · no-new-privileges                         │ │
│ │                                                         │ │          │ │ сеть agent-internal: нет выхода наружу и DNS             │ │
│ │ сокет %TEMP%\podman\                                    │ │          │ │ PID 1  tini                                              │ │
│ │   agents-api.sock                                       │ │          │ │ └─ agent-entrypoint (entrypoint.sh)                      │ │
│ │   (оставшийся файл → не стартует)                       │ │          │ │    ├─ exec sleep infinity  (держит контейнер)            │ │
│ │ слушает только на 127.0.0.1                             │ │          │ │    └─ tmux new -d -s orca                                │ │
│ │ проброс compose 127.0.0.1:6769:6769                     │ │          │ │ ┌─ tmux-сессия «orca» ─────────────────────────────────┐ │ │
│ │ 127.0.0.1:6769   orca ──────────────────────────────────┼─┼─ hvsock ─► │ │ orca-ide serve --port 6769                           │ │ │
│ └──▲──────────────────▲───────────────────────────────────┘ │          │ │ │   --pairing-address ws://127.0.0.1:6769              │ │ │
│    │ ws :6769         │ ssh :52230                          │          │ │ │ └─ orcad-server 0.0.0.0:6769                         │ │ │
│ ┌──┴─────────────┐ ┌──┴──────────────┐                      │          │ │ │    └─ daemon → терминалы и агенты                    │ │ │
│ │ Orca.exe       │ │ podman.exe      │                      │          │ │ └──────────────────────────────────────────────────────┘ │ │
│ │ десктоп, окно  │ │ build/run/exec: │                      │          │ │ ┌─ tmux-сессия «main» ─────────────────────────────────┐ │ │
│ │ свой рантайм   │ │   пользователь  │                      │          │ │ │ bash · claude · java · mvn · gradle · go · python    │ │ │
│ │ :6768 (занят)  │ │ machine/compose:│                      │          │ │ └──────────────────────────────────────────────────────┘ │ │
│ └────────────────┘ │   администратор │                      │          │ │ /repos ◄─ data/repos · ~/.claude ◄─ data/claude          │ │
│                    └─────────────────┘                      │          │ └─────┬────────────────────────────────────────────────────┘ │
│                                                             │          │       │ HTTP(S)_PROXY → egress:3128                          │          ┌── internet ────────┐
│                                                             │          │ ┌─────▼─ контейнер agent-box-egress-1 ─────────────────────┐ │          │                    │
│                                                             │          │ │ squid :3128 · домены из settings/egress/allowlist.txt    │ │          │ github, npm, pypi  │
│                                                             │          │ │ остальное → 403 + лог (podman logs agent-box-egress-1)   │ │          │ anthropic, maven   │
│                                                             │          │ │ сети agent-internal + outside ───────────────────────────┼─┼─gvproxy──► allowlist only     │
│                                                             │          │ └──────────────────────────────────────────────────────────┘ │          │                    │
│                                                             │          │                                                              │          └────────────────────┘
└─────────────────────────────────────────────────────────────┘          └──────────────────────────────────────────────────────────────┘
```

Orca на хосте подключается к `orca serve` в контейнере:
`Orca.exe → ws://127.0.0.1:6769 → gvproxy.exe → hvsock → VM → контейнер :6769 → orca-ide serve (tmux «orca»)`.
Порт 6768 занят собственным рантаймом десктопного Orca, 52230 — SSH в VM для `podman.exe`.
Весь трафик хост ↔ VM идёт через gvproxy: без него не работают ни 6769, ни 52230.
Выход контейнера agent в интернет — только через прокси egress со списком доменов (п. 8).

## 1. Права: что требует администратора

Управление Hyper-V разрешено только повышенным процессам. Пользователь **не** входит в группу
«Администраторы Hyper-V» (`S-1-5-32-578`): UAC эту группу не фильтрует, и с ней любой процесс без повышения
(в том числе агенты) мог бы управлять VM. Если пользователь уже в группе — убрать и перезайти в Windows:

```powershell
Remove-LocalGroupMember -SID 'S-1-5-32-578' -Member $env:USERNAME   # от имени администратора
```

| От имени администратора | Без прав администратора |
|---|---|
| `podman machine init / start / stop / rm / set / list / ssh` | `podman build`, `run`, `exec`, `ps`, `images`, `logs` |
| `podman compose ...` (запрашивает адрес машины через Hyper-V) | `scripts\build\build.ps1` / `build.sh` |
| Podman Desktop (запускать «от имени администратора», автозапуск при входе выключить) | работа в контейнере |

Без повышения `podman compose` падает с `get machine connection URI: could not find a matching machine for connection`.

Чтобы не открывать отдельную консоль администратора, можно включить встроенный `sudo` Windows 11:
«Параметры → Система → Для разработчиков → Включить sudo» (режим «В новом окне» безопаснее «Встроенного»),
дальше `sudo podman compose ...` из обычной консоли.

Консоль от имени администратора открывается в `C:\Windows\System32`: перенаправление вида `... > podman` создаст
там пустой файл `podman`, который PowerShell найдёт раньше `podman.exe` (см. «Проблемы»).

### Скрипты PowerShell

По умолчанию в Windows политика `Restricted` — `.ps1` не запускаются («выполнение сценариев отключено в этой системе»),
в том числе `build.ps1` и профиль `Documents\WindowsPowerShell\profile.ps1`. Разрешить локальные скрипты:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # постоянно для пользователя, админ не нужен
Set-ExecutionPolicy -Scope Process RemoteSigned       # только текущее окно
```

`RemoteSigned`: локальные скрипты запускаются, скачанные из интернета (с пометкой `Zone.Identifier`) — только
с цифровой подписью; снять пометку с доверенного файла — `Unblock-File`. Разово без изменения политики:
`powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build\build.ps1`.

## 2. Создание Podman-машины

PowerShell **от имени администратора** (`init` пишет в реестр `HKLM`):

```powershell
podman machine init agents --provider hyperv --image docker://quay.io/podman/machine-os:6.1 --cpus 6 --memory 8192 --swap 0 --disk-size 60 -v A:\orca\docker:/mnt/a/orca/docker
```

| Параметр | Значение |
|---|---|
| `--provider hyperv` | Hyper-V только для этой машины, провайдер по умолчанию не меняется |
| `--image` | Fedora CoreOS от команды Podman, версия под клиент 6.1 |
| `--cpus 6` | 6 виртуальных CPU |
| `--memory 8192` | 8 ГБ памяти |
| `--swap 0` | без swap |
| `--disk-size 60` | диск 60 ГБ |
| `-v` | единственная папка Windows, видимая машине. Цель обязана быть `/mnt/<диск>/<путь>` той же папки: compose переводит `A:\orca\docker\settings` в `/mnt/a/orca/docker/settings` |

Монтирование меняется только пересозданием машины (`rm` + `init`), образы и named volume при этом удаляются.
Нужна именно папка проекта: из неё монтируются `settings/` и `data/`.

Hyper-V не должен запускать VM сам при загрузке Windows: так VM работает без gvproxy и недоступна (см. «Проблемы»).

```powershell
Set-VM -Name agents -AutomaticStartAction Nothing
```

## 3. Запуск машины

От имени администратора:

```powershell
$env:CONTAINERS_MACHINE_PROVIDER = 'hyperv'   # только для текущего окна
podman machine start agents
podman system connection default agents
```

Проверить, что машина запущена и доступна:

```powershell
podman machine list                                                 # админ: LAST UP = Currently running
Test-NetConnection 127.0.0.1 -Port 52230 -InformationLevel Quiet    # без админа: True — VM принимает подключения
```

`Currently running` значит только, что VM включена в Hyper-V. Подключиться к ней можно, когда на хосте работает
gvproxy (проброс SSH-порта). Порт (здесь 52230) назначается при `init` и записан в подключении `agents`
(`podman system connection list`); скрипты его не содержат.

## 4. Проверка

От имени администратора:

```powershell
podman machine ssh agents getenforce          # Enforcing
podman network create nettest; podman run --rm --network nettest docker.io/library/debian:trixie-slim getent hosts deb.debian.org; podman network rm nettest
```

Последняя команда должна вывести IP-адрес `deb.debian.org`.

## 5. Сборка образа

Без прав администратора, машина `agents` должна быть запущена (п. 3):

```powershell
.\scripts\build\build.ps1         # или ./scripts/build/build.sh
Copy-Item .env.example .env       # заполнить переменные
```

Из `cmd`: `powershell -NoProfile -ExecutionPolicy Bypass -File A:\orca\docker\scripts\build\build.ps1`.
Скрипт сам переходит в корень репозитория и берёт `podman.exe` (файлы без расширения в PATH пропускает).
Собираются два образа: `localhost/agent-box` и прокси `localhost/agent-box-egress` (п. 8).
Сборка ходит в интернет напрямую — ограничение п. 8 действует только на запущенный контейнер agent.

## 6. Запуск контейнера

От имени администратора. Команды работают из любой папки и в `cmd`, и в PowerShell: `-f` задаёт файл,
а `.env` и относительные пути берутся из папки `compose.yaml`.

```bat
podman compose -f A:\orca\docker\compose.yaml up -d                              # поднять
podman compose -f A:\orca\docker\compose.yaml up -d --force-recreate             # пересоздать (новый образ, порты)
podman compose -f A:\orca\docker\compose.yaml ps                                 # статус
podman compose -f A:\orca\docker\compose.yaml logs --tail 100                    # логи
podman compose -f A:\orca\docker\compose.yaml exec agent tmux new -A -s main     # подключиться
podman compose -f A:\orca\docker\compose.yaml down                               # остановить
```

Без прав администратора то же через обычный podman: `podman exec -it agent-box-agent-1 tmux new -A -s main`.

`~/.claude` контейнера смонтирован из `data/claude` (`CLAUDE_CONFIG_DIR`, туда же попадает `.claude.json`):
логин, сессии, история и `settings.json` (в него пишут Orca и сам Claude) переживают пересоздание контейнера.
Поверх него только для чтения монтируется статический `settings/claude/CLAUDE.md` из git: агенты его не изменят.
Это отдельный конфиг, не `~/.claude` хоста: хуки хоста с путями Windows в Linux не работают, а запись агентов
в конфиг хоста дала бы им выполнение команд на Windows.
`userns_mode: keep-id` нужен, чтобы agent мог писать в папки, смонтированные с Windows.

Где хранятся данные контейнера:

| В контейнере | Где | Что |
|---|---|---|
| `~/.claude` | `data/claude` на Windows | логин, сессии, история, `settings.json` Claude Code |
| `~/.claude/CLAUDE.md` | `settings/claude/CLAUDE.md`, только чтение | инструкции агентам (в git) |
| `/repos` | `data/repos` на Windows | git-репозитории всех агентов (рабочая папка контейнера, `$REPOS_DIR`) |
| `~/orca/workspaces` | `data/repos/orca-worktrees` на Windows | worktree, которые создаёт Orca (её `workspaceDir` по умолчанию) |
| `~/.config/orca`, `~/.orca` | `data/orca/config`, `data/orca/home` на Windows | сессии и рабочие пространства Orca, история терминалов, сопряжение, секреты orcad |
| `~/.local/state/bash` | `data/bash` на Windows | история bash (`HISTFILE`) |
| `~/.config/orca/orcad-artifacts` | named volume `agent-box_orcad-artifacts` | рантайм orcad (~150 МБ), скачивается с nodejs.org |
| остальной `/home/agent` | named volume `agent-box_agent-home` | кэши npm, Maven, Gradle, Go, `~/.m2/settings.xml` |

Всё это переживает `up --force-recreate` и `down`. Named volume удаляются `down -v`, `podman volume rm` и
пересозданием машины; `data/` на Windows — только вручную. Содержимое `/home/agent` из образа копируется в том
только при первом создании: изменения домашней папки в новом образе в существующий том не попадут.

Агенты клонируют репозитории в `/repos`: так написано в `settings/claude/CLAUDE.md` (инструкции Claude Code,
правятся без пересборки), `/repos` — рабочая папка контейнера, путь есть в `$REPOS_DIR`. Это правило для агентов,
а не запрет: клонировать в другое место технически можно, но такие репозитории пропадут при пересоздании контейнера.
Сам `/repos` — тоже 9p: регистр в именах файлов не различается (как в NTFS), установка зависимостей и сборки
медленнее, чем на диске VM.

`data/` подключается по 9p (п. 2): SQLite-базы Orca в режиме WAL и её unix-сокеты (`daemon/*.sock`, `o-*.sock`)
на 9p могут работать ненадёжно. Если `orca serve` не стартует (`tmux attach -t orca`) или базы повреждаются —
перенести `~/.config/orca` в named volume.

```bat
podman volume ls                                                  :: тома agent-box_*
podman volume export agent-box_agent-home -o A:\backup\home.tar   :: резервная копия на Windows
```

### Как устроен контейнер

```
tini                                  PID 1: передаёт сигналы, убирает зомби-процессы
└── agent-entrypoint                  scripts/build/entrypoint.sh: запускает tmux-сессию orca, затем exec основной команды
    └── sleep infinity                command из compose.yaml: держит контейнер запущенным
tmux: orca  — orca-ide serve          (п. 7)
tmux: main  — ваша работа             (через exec)
```

Контейнер живёт, пока жив главный процесс. `bash` из `CMD` образа без терминала сразу завершился бы,
поэтому compose запускает `sleep infinity` — бесконечное ожидание без нагрузки, а работа идёт через `exec`.

`podman compose exec agent tmux new -A -s main`:

| Часть | Значение |
|---|---|
| `podman compose exec` | выполнить команду в уже запущенном контейнере сервиса |
| `agent` | имя сервиса из `compose.yaml` (`services: agent`) |
| `tmux new` | создать tmux-сессию |
| `-A` | если сессия уже есть — подключиться к ней, а не создавать новую |
| `-s main` | имя сессии `main` |

Отключиться, не останавливая работу: `Ctrl+B`, затем `D`. Процессы в сессии (агенты) продолжают работать,
повторный `attach` вернёт в ту же сессию.

tmux запускает login-shell, а `/etc/profile` Debian сбрасывает `PATH`; образ возвращает его через
`/etc/profile.d/00-agent-box-path.sh`, поэтому `java`, `mvn`, `gradle`, `go` доступны и в tmux.

## 7. Orca

CLI Orca в образе называется `orca-ide` (не `orca`). `orca-ide open` в контейнере не работает: это десктопное
приложение, а дисплея нет (`Timed out waiting for an Orca desktop window`). Вместо него при старте контейнера
`scripts/build/entrypoint.sh` запускает в tmux-сессии `orca` сервер без окна:

```
orca-ide serve --port 6769 --pairing-address ws://127.0.0.1:6769
```

Окно — десктопный Orca на Windows, агенты и терминалы — в контейнере. Порт пробрасывается только на
`127.0.0.1` (`compose.yaml`, секция «сеть»). Порт **6769**, а не 6768 по умолчанию: 6768 на Windows занимает
рантайм десктопного Orca, и с ним compose падает с `listen tcp 127.0.0.1:6768: bind: Only one usage of each socket address`.

Подключение:

1. Посмотреть код сопряжения (без админа):
   ```bat
   podman exec -it agent-box-agent-1 tmux attach -t orca
   ```
   Скопировать `orca://pair?code=...`, отключиться `Ctrl+B`, `D`. Код новый при каждом запуске сервера.
2. В десктопном Orca добавить удалённое окружение по этому коду.

Управление сессией:

```bat
podman exec agent-box-agent-1 tmux ls                     # список сессий
podman exec agent-box-agent-1 tmux kill-session -t orca   # остановить сервер
podman exec agent-box-agent-1 tmux new -d -s orca "orca-ide serve --port 6769 --pairing-address ws://127.0.0.1:6769"   # запустить вручную
```

Если сервер упал, сессия остаётся открытой (`remain-on-exit`) с его выводом. Настройки в `.env`:

| Переменная | По умолчанию | Значение |
|---|---|---|
| `ORCA_SERVE` | `1` | `0` — не запускать сервер при старте |
| `ORCA_PORT` | `6769` | порт в контейнере и на `127.0.0.1` Windows |
| `ORCA_PAIRING_ADDRESS` | `ws://127.0.0.1:$ORCA_PORT` | адрес, который получит Orca на Windows |

Флаг `--grant-desktop-control` не используется: подключённый клиент не управляет «рабочим столом» контейнера.
Предупреждения в выводе сервера не мешают работе: `Installed Electron browser provider unavailable` — нет дисплея,
встроенный браузер Orca недоступен; `[agent-state-rules] download failed: HTTP 404` — не скачались доп. правила.

## 8. Доступ в интернет: allowlist

Контейнер agent ходит в интернет только через прокси `egress` (squid) и только на домены из
`settings/egress/allowlist.txt`. Всё остальное получает 403 и записывается в лог.

```
┌─ agent ───────────────────────┐  сеть agent-internal   ┌─ egress (squid :3128) ─────┐  сеть outside
│ claude, npm, pip, git, mvn …  │  internal: нет выхода  │ allowlist.txt              │ ──────────────► интернет
│ HTTPS_PROXY=http://egress:3128│ ─► и внешнего DNS ────►│ остальное → 403 + лог      │ (только из списка)
└───────────────────────────────┘                        └────────────────────────────┘
        ▲ 127.0.0.1:6769 (Orca) — проброс порта во внутреннюю сеть работает
```

- **Сеть `agent-internal`** (`internal: true`) не имеет маршрута наружу и внешнего DNS. Обойти прокси нельзя:
  `curl --noproxy '*'`, ssh, произвольные TCP-порты не работают. `egress` подключён к ней и к сети `outside`.
- **HTTPS не расшифровывается**: squid видит домен из `CONNECT`, сертификаты не подменяются.
  Разрешены порты 80 и 443, `CONNECT` — только на 443. `git` — только по https, не по ssh.
- **Прокси в agent** задаёт `compose.yaml` (`environment`, важнее `.env`): `HTTP(S)_PROXY`, `NO_PROXY`,
  `NODE_USE_ENV_PROXY=1` (без него `fetch` в Node.js прокси не использует). Maven и Gradle переменные окружения
  не читают: `scripts/build/entrypoint.sh` при старте создаёт `~/.m2/settings.xml` и `~/.gradle/gradle.properties` с прокси,
  если этих файлов ещё нет.

Проверено: claude (api.anthropic.com), npm, pip, go, git (https), Maven, Gradle и `orca serve` работают;
`example.com` → 403; прямой выход мимо прокси → нет соединения.

Стартовый список (`settings/egress/allowlist.txt`): Anthropic/Claude, `nodejs.org` (рантайм для `orca serve`), GitHub,
npm, PyPI, Go proxy, Maven Central, Gradle, Kubernetes/Helm. Формат: `.example.com` — домен и поддомены,
`example.com` — только сам домен; один домен в обеих формах squid сочтёт дублем.

### Изменить список

`settings/egress/squid.conf` и `allowlist.txt` не входят в образ: `compose.yaml` монтирует их в egress
только для чтения. Для этого папка проекта должна быть смонтирована в машину (п. 2, `-v A:\orca\docker:/mnt/a/orca/docker`),
иначе egress не создаётся (`statfs ... settings/egress/...`) и у agent нет интернета.

1. Посмотреть отказы (без админа):
   ```bat
   podman logs agent-box-egress-1 | findstr DENIED
   ```
   Строка `TCP_DENIED/403 CONNECT nodejs.org:443` — домен, который нужно добавить.
2. Дописать домен в `settings/egress/allowlist.txt`.
3. Перезапустить egress (без админа, пересборка не нужна):
   ```bat
   podman restart agent-box-egress-1
   podman logs --tail 20 agent-box-egress-1
   ```
   При старте squid проверяет конфиг (`squid -k parse`): с ошибкой в `squid.conf` или списке контейнер
   не запустится, причина — в `podman logs`.

Корпоративный прокси наверху — `cache_peer` в `settings/egress/squid.conf`; `HTTP_PROXY` в `.env` игнорируется.

## 9. Langfuse: трейсы Claude Code

Каждый ответ Claude Code в контейнере отправляется в Langfuse как трейс: промпт, ответ, вызовы инструментов.
Используется официальный хук Stop из документации Langfuse
(<https://langfuse.com/integrations/developer-tools/claude-code>):

- скрипт `scripts/build/langfuse_hook.py` встроен в образ (`/usr/local/lib/agent-box/langfuse_hook.py`),
  SDK `langfuse==4.18.0` — в отдельном venv `/opt/langfuse-hook` (скрипт привязан к SDK 4.x, версия — `LANGFUSE_VERSION` в `images/Dockerfile`);
- хук зарегистрирован в `settings/managed-settings.json` рядом с dcg: агенты не могут его отключить;
- включение и ключи — в `.env` (не в git), `env_file` передаёт их в контейнер:
  ```
  TRACE_TO_LANGFUSE=true
  LANGFUSE_PUBLIC_KEY=pk-lf-...
  LANGFUSE_SECRET_KEY=sk-lf-...
  LANGFUSE_BASE_URL=https://cloud.langfuse.com
  ```
  Без `TRACE_TO_LANGFUSE=true` хук сразу завершается; при недоступном Langfuse не мешает работе (fail-open, flush до 5 с);
- домен сервера — в `settings/egress/allowlist.txt` (`cloud.langfuse.com`); SDK ходит через `HTTPS_PROXY`.

Лог и состояние хука — `~/.claude/state/` (`data/claude/state` на Windows), подробный лог — `CC_LANGFUSE_DEBUG=true`.
Ключи видны агентам в окружении контейнера: используйте отдельный проект Langfuse для агентов.

`orca.yaml` (секция `scripts.setup`, которую Orca предлагает при создании worktree) для этого не подходит: он лежит
в корне каждого репозитория и выполняется при создании worktree — там место установке зависимостей проекта
(`npm install`, `uv sync`), а не настройке агента.

## 10. Мониторинг: профиль monitoring

Сервисы мониторинга описаны в `compose.yaml` с `profiles: [monitoring]` и без профиля не запускаются.
От имени администратора:

```bat
podman compose -f A:\orca\docker\compose.yaml --profile monitoring up -d
podman compose -f A:\orca\docker\compose.yaml --profile monitoring down
```

Чтобы не писать `--profile` каждый раз — `COMPOSE_PROFILES=monitoring` в `.env`.
Образ Grafana собирает `scripts\build\build.ps1` (`localhost/agent-box-grafana`), остальные образы скачиваются.

```
 exporters / приложения                     otel-collector                         хранилища
 squid-exporter (egress:9301) ─ scrape ─►┐                              ┌─► VictoriaMetrics :8428  ─┐
 cAdvisor :8080 ──────────────── scrape ─►│  receivers:                  │                            │
 Victoria*, vmauth, Grafana ──── scrape ─►│   prometheus (scrape)        ├─► VictoriaLogs    :9428  ─┼─► vmauth :8427 (VMUI)
 node-exporter ◄─ otel-agent ─── OTLP ──►│   otlp :4317/:4318           │                            │   Grafana :3000
 (сеть VM)        (сеть VM)              │   prometheus_remote_write    └─► VictoriaTraces  :10428 ─┘
 приложения в agent ───────────── OTLP ──►│     :9090
```

| Сервис | Порт на 127.0.0.1 | Что делает |
|---|---|---|
| `otel-collector` | 4317, 4318, 9090, 8888 | единая точка сбора: OTLP (метрики, логи, трейсы), Prometheus remote write 2.0 (push), scrape экспортеров (pull); свои метрики — 8888 |
| `otel-agent` | — (сеть VM) | забирает метрики node-exporter и передаёт в otel-collector по OTLP |
| `node-exporter` | — (сеть VM, 127.0.0.1:9100 внутри VM) | метрики самой VM: CPU, память, диски, сеть |
| `cadvisor` | 8080 | метрики контейнеров по cgroups, с именами из podman |
| `squid-exporter` | 9301 (порт egress) | счётчики squid из cache manager: запросы, трафик, время ответа, соединения, память |
| `victoria-metrics` | 8428 | метрики, VMUI `/vmui/` |
| `victoria-logs` | 9428 | логи, VMUI `/select/vmui/` |
| `victoria-traces` | 10428 | трейсы, VMUI `/select/vmui/`, Jaeger API `/select/jaeger` |
| `vmauth` | 8427 | один вход во все VMUI (ниже) |
| `grafana` | 3000 | дашборды; логин `admin`/`admin` или `GRAFANA_ADMIN_*` в `.env` |

**Один VMUI.** У каждого компонента Victoria свой встроенный VMUI, vmauth собирает их на одном порту:
<http://127.0.0.1:8427/vmui/> — метрики, <http://127.0.0.1:8427/logs/select/vmui/> — логи,
<http://127.0.0.1:8427/traces/select/vmui/> — трейсы (`settings/monitoring/vmauth.yaml`).

**Grafana.** Источники данных создаются из `settings/monitoring/grafana/provisioning`: VictoriaMetrics
(тип Prometheus), VictoriaLogs (плагин `victoriametrics-logs-datasource`), VictoriaTraces (тип Jaeger).
БД не нужна: пользователи и дашборды — во встроенной SQLite в `data/monitoring/grafana`. Готовые дашборды
импортируются по ID (например, Node Exporter Full — `1860`); метки `job`/`instance` коллектор
восстанавливает из OTLP-атрибутов, поэтому такие дашборды работают.

**Без интернета.** Сеть `monitoring` — `internal: true`: ни Grafana, ни хранилища не выходят наружу. Плагин
VictoriaLogs ставится при сборке образа (`images/monitoring/grafana.Dockerfile`, версия `VICTORIALOGS_PLUGIN_VERSION`),
проверки обновлений и статистика Grafana выключены. node-exporter и otel-agent работают в сети VM, но наружу не ходят.

**Prometheus-формат.** Принимается двумя способами: scrape (добавить job в `settings/monitoring/otel-collector.yaml`)
и push через remote write на `http://127.0.0.1:9090` (из agent — `http://otel-collector:9090`). Приёмник
поддерживает только Remote Write 2.0: в Prometheus — `protobuf_message: io.prometheus.write.v2.Request` в `remote_write`.

**Отправка из agent.** otel-collector подключён к сети `agent-internal`: приложения в контейнере agent шлют OTLP на
`http://otel-collector:4318` без прокси (`otel-collector` в `NO_PROXY`).

**Особенности rootless podman:**
- bridge-сети не видят сеть самой VM, поэтому node-exporter (ему нужна сеть VM) читает otel-agent в той же сети и
  отправляет в опубликованный порт коллектора `127.0.0.1:4318`;
- cAdvisor не может следить за корнем cgroup: ему монтируется поддерево пользователя `core`
  (`/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service`), где живут все контейнеры, SELinux-метка
  отключена только для него, сокет podman — для имён контейнеров (даёт доступ к podman, поэтому cAdvisor только
  во внутренней сети);
- squid-exporter работает в сетевом пространстве egress: cache manager доступен только с localhost
  (`http_access allow localhost manager` в `settings/egress/squid.conf`), порт 9301 публикуется у egress.

Данные `data/monitoring` лежат на Windows (9p): VictoriaMetrics/Logs/Traces и SQLite Grafana на 9p медленнее
и менее надёжны, чем на диске VM. Срок хранения — `METRICS_RETENTION` (30d), `LOGS_RETENTION` (14d),
`TRACES_RETENTION` (7d) в `.env`.

## 11. PostgreSQL 18

Сервис `postgres` (`postgres:18.6-trixie`) запускается вместе с agent, без профиля.

| Откуда | Адрес |
|---|---|
| контейнер agent | `postgres:5432` (сеть `agent-internal`), клиент `psql`/`createdb` есть в образе |
| Windows | `127.0.0.1:5432` (`POSTGRES_PORT` в `.env`) |

- Пользователь, пароль и БД — `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` в `.env`. Они применяются только
  при первом запуске, когда `data/postgres` пуста; потом пароль меняется через `ALTER USER`. Переменные из `.env`
  видны и в agent, поэтому агенты подключаются без отдельной настройки (`settings/claude/CLAUDE.md`).
- Данные — `data/postgres` на Windows. В образе 18 `PGDATA=/var/lib/postgresql/18/docker`, поэтому монтируется
  родитель `/var/lib/postgresql`: обновление на 19 сможет положить данные рядом в `19/docker`.
- Права: `userns_mode: keep-id` и `user: "1000:1000"`, как у agent: владелец папок с Windows (пользователь VM)
  совпадает с процессом postgres. Образ поддерживает произвольный uid.
- Нет выхода в интернет: только сеть `agent-internal`.

`data/postgres` лежит на 9p: PostgreSQL требует права `0700` на каталог данных и надёжный `fsync`. Если сервер
не стартует с `data directory ... has invalid permissions` или пишет ошибки ввода-вывода — перенести данные в
named volume (`postgres-data:/var/lib/postgresql`).

```bat
podman exec -it agent-box-postgres-1 psql -U postgres                 :: консоль
podman exec agent-box-postgres-1 pg_dumpall -U postgres > dump.sql    :: резервная копия на Windows
```

## Проблемы
### `machine is not listening on ssh port`, а `machine list` показывает `Currently running`

На хосте не работает gvproxy (проброс SSH-порта и сети в VM), в VM падает `vsock-network.service`.
Частая причина — после перезагрузки Windows остался файл сокета, и gvproxy сразу завершается
(`%TEMP%\podman\gvproxy.log`: `listen unix ...agents-api.sock: bind: Only one usage of each socket address`).

```bat
podman machine stop agents
powershell -NoProfile -Command "(Get-VM agents).State"          :: Off; если Running — Stop-VM agents -TurnOff -Force
del "%TEMP%\podman\agents-api.sock"
podman machine start agents
```

Диагностика: `podman --log-level=debug machine start agents > "%TEMP%\podman-start.log" 2>&1`,
лог gvproxy — `%TEMP%\podman\gvproxy.log`, консоль VM — `vmconnect localhost agents`
(`systemctl --failed`, `ip -br a`: должен быть `tap0` с `192.168.127.2`).

### `unable to start "agents": already running`

VM включена в Hyper-V без gvproxy (осталась от неудачного старта или запущена Hyper-V при загрузке).
`podman machine stop agents`, затем `start`. Автозапуск Hyper-V выключить (п. 2).

### `Cannot connect to Podman ... dial tcp 127.0.0.1:52230: ... actively refused it`

Машина не запущена или gvproxy не работает — см. п. 3 и проблемы выше. `podman system connection list`
работает и при выключенной машине: она только читает конфиг.

### `Cannot run a document in the middle of a pipeline: C:\Windows\System32\podman`

В `System32` пустой файл `podman` без расширения (обычно результат перенаправления `>` в консоли администратора).
PowerShell находит его раньше `podman.exe`. Удалить от имени администратора: `del C:\Windows\System32\podman`.

### `statfs /mnt/a/orca/docker/settings/...: no such file or directory` (или `input/output error`)

Папка проекта не смонтирована в VM по пути, который ожидает compose (п. 2, параметр `-v`).
Та же ошибка с `settings/egress/squid.conf` — у egress (п. 8): без монтирования он не запускается.

### `java: command not found` / `orca: command not found` в контейнере

`java` — образ собран до исправления `PATH` для login-shell: пересобрать и пересоздать контейнер.
`orca` — CLI называется `orca-ide`.

### В контейнере что-то не скачивается, `Could not resolve host`, `fetch failed`, 403

Домена нет в allowlist (п. 8): `podman logs agent-box-egress-1 | findstr DENIED`. `Could not resolve host`
без записи в логе squid — программа не использует прокси (нужны `HTTPS_PROXY` или свои настройки прокси).
`orca serve` без `nodejs.org` падает с `the orcad slot ... could not be prepared: fetch failed`.

## Удаление машины

PowerShell от имени администратора:

```powershell
$env:CONTAINERS_MACHINE_PROVIDER = 'hyperv'
podman machine stop agents
podman machine rm agents
```

## Полезное

1. Agentic Design Patterns - https://mokevnin.github.io/agentic-coding-design-patterns/ru/
2. https://martinfowler.com/articles/structured-prompt-driven/
