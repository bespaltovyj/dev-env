# Установка agent-box на Windows (Podman + Hyper-V)

## Требования

- Windows 10/11 Pro или Enterprise с включённым Hyper-V
- Установленный Podman (CLI), при желании Podman Desktop
- Для работы с Orca — десктопный Orca на Windows

## Архитектура

```
┌── host ─────────────────────────────────────────────────────┐          ┌── Hyper-V VM «agents»: Fedora CoreOS ────────────────────────┐
│                                                             │          │                                                              │
│ ┌─ gvproxy.exe ───────────────────────────────────────────┐ │          │ vsock-network.service → tap0 192.168.127.2                   │
│ │ 127.0.0.1:52230  SSH ───────────────────────────────────┼─┼─ hvsock ─► sshd :22  (podman API, rootless, core)                       │
│ │ hvsock 0000DD87-… — сеть VM                             │ │          │ /mnt/a/orca/docker  ◄─ 9p ◄─ A:\podman (хост)                │
│ │                                                         │ │          │                                                              │
│ │ 1. sudo podman machine start                            │ │          │                                                              │
│ │ 2. .\build.ps1 или ./build.sh                           │ │          │ ┌─ контейнер agent-box-agent-1 ────────────────────────────┐ │
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
│ └────────────────┘ │   администратор │                      │          │ │ /home/agent, /workspaces — в контейнере (volumes выкл.)  │ │
│                    └─────────────────┘                      │          │ └─────┬────────────────────────────────────────────────────┘ │
│                                                             │          │       │ HTTP(S)_PROXY → egress:3128                          │          ┌── internet ────────┐
│                                                             │          │ ┌─────▼─ контейнер agent-box-egress-1 ─────────────────────┐ │          │                    │
│                                                             │          │ │ squid :3128 · только домены из egress/allowlist.txt      │ │          │ github, npm, pypi  │
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
| `podman compose ...` (запрашивает адрес машины через Hyper-V) | `build.ps1` / `build.sh` |
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
`powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1`.

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
| `-v` | единственная папка Windows, видимая машине. Цель обязана быть `/mnt/<диск>/<путь>` той же папки: compose переводит `A:\orca\docker\data` в `/mnt/a/orca/docker/data` |

Монтирование меняется только пересозданием машины (`rm` + `init`), образы при этом удаляются.
Чтобы VM видела только данные, а не исходники и `.env`, можно смонтировать отдельную папку
(`-v A:\podman:/mnt/a/podman`) и указать в `.env` `WORKSPACES_DIR=A:\podman\workspaces`, `AGENT_HOME_DIR=A:\podman\home`.

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
.\build.ps1                       # или ./build.sh
Copy-Item .env.example .env       # заполнить переменные
```

Из `cmd`: `powershell -NoProfile -ExecutionPolicy Bypass -File A:\orca\docker\build.ps1`.
Скрипт сам переходит в свою папку и берёт `podman.exe` (файлы без расширения в PATH пропускает).
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

Пока `volumes:` в `compose.yaml` закомментирован, `/home/agent` и `/workspaces` живут только в контейнере:
пересоздание контейнера стирает их (в том числе логин Claude).

### Как устроен контейнер

```
tini                                  PID 1: передаёт сигналы, убирает зомби-процессы
└── agent-entrypoint                  entrypoint.sh: запускает tmux-сессию orca, затем exec основной команды
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
`entrypoint.sh` запускает в tmux-сессии `orca` сервер без окна:

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
`egress/allowlist.txt`. Всё остальное получает 403 и записывается в лог.

```
┌─ agent ───────────────────────┐  сеть agent-internal   ┌─ egress (squid :3128) ─────┐  сеть outside
│ claude, npm, pip, git, mvn …  │  internal: нет выхода  │ egress/allowlist.txt       │ ──────────────► интернет
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
  не читают: `entrypoint.sh` при старте создаёт `~/.m2/settings.xml` и `~/.gradle/gradle.properties` с прокси,
  если этих файлов ещё нет.

Проверено: claude (api.anthropic.com), npm, pip, go, git (https), Maven, Gradle и `orca serve` работают;
`example.com` → 403; прямой выход мимо прокси → нет соединения.

Стартовый список (`egress/allowlist.txt`): Anthropic/Claude, `nodejs.org` (рантайм для `orca serve`), GitHub,
npm, PyPI, Go proxy, Maven Central, Gradle, Kubernetes/Helm. Формат: `.example.com` — домен и поддомены,
`example.com` — только сам домен; один домен в обеих формах squid сочтёт дублем.

### Изменить список

Список встроен в образ (bind mount с хоста пока не работает, см. п. 2):

1. Посмотреть отказы (без админа):
   ```bat
   podman logs agent-box-egress-1 | findstr DENIED
   ```
   Строка `TCP_DENIED/403 CONNECT nodejs.org:443` — домен, который нужно добавить.
2. Дописать домен в `egress/allowlist.txt`.
3. Пересобрать (без админа) и пересоздать egress (от имени администратора):
   ```bat
   powershell -NoProfile -ExecutionPolicy Bypass -File A:\orca\docker\build.ps1
   podman compose -f A:\orca\docker\compose.yaml up -d --force-recreate egress
   ```
   Ошибка в `squid.conf` или списке ломает сборку (`squid -k parse`), а не запуск.

Корпоративный прокси наверху — `cache_peer` в `egress/squid.conf`; `HTTP_PROXY` в `.env` игнорируется.

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

### `statfs /mnt/a/orca/docker/data/home: no such file or directory`

Папка проекта не смонтирована в VM по пути, который ожидает compose (п. 2, параметр `-v`).

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
