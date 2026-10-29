# Сборка agent-box: common -> компоненты (параллельно) -> итоговый образ и egress.
#
#   .\scripts\build\build.ps1                                  # всё
#   .\scripts\build\build.ps1 -BuildArgs 'GO_VERSION=1.27.3'   # аргументы передаются во все сборки
#   .\scripts\build\build.ps1 -Engine docker -Jobs 8
#
# Пути (images\, .build-logs) считаются от корня репозитория, текущая папка не важна.
[CmdletBinding()]
param(
    [string]   $Engine    = 'podman',
    [string]   $Prefix    = 'localhost/agent-box',
    [string]   $Image     = 'localhost/agent-box:latest',
    [string]   $EgressImage = 'localhost/agent-box-egress:latest',
    [string]   $GrafanaImage = 'localhost/agent-box-grafana:latest',
    [int]      $Jobs      = 4,
    [string]   $LogDir    = '.build-logs',
    [string[]] $BuildArgs = @()
)

# Continue: в PowerShell 5.1 перенаправленный stderr podman при Stop прерывает скрипт;
# результат сборок проверяется по $LASTEXITCODE
$ErrorActionPreference = 'Continue'

# Корень репозитория: скрипт лежит в scripts\build
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
Set-Location $Root

# Волны: внутри волны компоненты собираются параллельно
$Wave1 = @('node', 'jdk17', 'jdk21', 'jdk25', 'maven', 'gradle', 'go', 'uv', 'ruff', 'kubectl', 'helm', 'orca', 'dcg', 'claude')
$Wave2 = @('pytest')   # зависит от uv

# Зависимости компонентов от других компонентов
$Deps = @{ pytest = @('uv') }

$CommonArgs = @()
if ($Engine -eq 'podman') { $CommonArgs += @('--format', 'docker') }
foreach ($a in $BuildArgs) { $CommonArgs += @('--build-arg', $a) }

New-Item -ItemType Directory -Force $LogDir | Out-Null
# Только .exe: посторонний файл без расширения раньше в PATH (например, System32\podman) не подхватится
$EnginePath = (Get-Command $Engine -CommandType Application | Where-Object Extension -eq '.exe' | Select-Object -First 1).Source
$LogRoot = (Resolve-Path $LogDir).Path

function Get-ContextArgs([string[]] $Names) {
    $out = @()
    foreach ($n in $Names) { $out += @('--build-context', "$n=docker-image://$Prefix/${n}:latest") }
    return $out
}

function Get-ComponentArgs([string] $Name) {
    # settings: статические настройки репозитория (common копирует settings/apt)
    $argv = @('build') + $CommonArgs + @('--build-arg', "COMMON_IMAGE=$Prefix/common:latest",
        '--build-context', 'settings=settings')
    if ($Deps.ContainsKey($Name)) { $argv += Get-ContextArgs $Deps[$Name] }
    # images/<группа>/<name>.Dockerfile
    $file = Get-ChildItem -Path images -Recurse -Filter "$Name.Dockerfile" | Select-Object -First 1
    if (-not $file) { throw "нет images/**/$Name.Dockerfile" }
    $rel = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
    $argv += @('-t', "$Prefix/${Name}:latest", '-f', $rel, 'images')
    return $argv
}

$BuildJob = {
    param($Exe, $Dir, $Argv, $Log)
    Set-Location $Dir
    & $Exe @Argv 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath $Log -Encoding utf8
    $LASTEXITCODE
}

function Show-Failure([string] $Name) {
    Write-Host "!! ${Name}: ошибка сборки, лог $LogDir\$Name.log" -ForegroundColor Red
    Get-Content (Join-Path $LogRoot "$Name.log") -Tail 20 | Write-Host
}

function Invoke-Wave([string[]] $Names) {
    $running = @{}
    $failed = @()
    foreach ($n in $Names) {
        while (@($running.Values | Where-Object State -eq 'Running').Count -ge $Jobs) {
            Wait-Job -Job @($running.Values) -Any | Out-Null
        }
        Write-Host "  -> $n"
        $running[$n] = Start-Job -ScriptBlock $BuildJob `
            -ArgumentList $EnginePath, $Root, (Get-ComponentArgs $n), (Join-Path $LogRoot "$n.log")
    }
    foreach ($n in @($running.Keys)) {
        $code = Receive-Job -Job $running[$n] -Wait
        Remove-Job -Job $running[$n]
        if ($code -ne 0) { $failed += $n }
    }
    if ($failed.Count -gt 0) {
        $failed | ForEach-Object { Show-Failure $_ }
        exit 1
    }
}

Write-Host '== common'
$code = & $BuildJob $EnginePath $Root (Get-ComponentArgs 'common') (Join-Path $LogRoot 'common.log')
if ($code -ne 0) { Show-Failure 'common'; exit 1 }

Write-Host '== компоненты'
Invoke-Wave $Wave1
Invoke-Wave $Wave2

Write-Host "== $Image"
$argv = @('build') + $CommonArgs + (Get-ContextArgs ($Wave1 + $Wave2)) + @('--build-arg', "COMMON_IMAGE=$Prefix/common:latest", '-t', $Image, '-f', 'images/Dockerfile', '.')
& $EnginePath @argv 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath (Join-Path $LogRoot 'final.log')
if ($LASTEXITCODE -ne 0) { exit 1 }

# Прокси для выхода agent в интернет (конфиг монтирует compose.yaml из settings/egress)
Write-Host "== $EgressImage"
$argv = @('build') + $CommonArgs + @('--build-arg', "COMMON_IMAGE=$Prefix/common:latest", '-t', $EgressImage, '-f', 'images/egress/Dockerfile', 'images/egress')
$code = & $BuildJob $EnginePath $Root $argv (Join-Path $LogRoot 'egress.log')
if ($code -ne 0) { Show-Failure 'egress'; exit 1 }

# Grafana для профиля monitoring: плагин VictoriaLogs ставится при сборке
Write-Host "== $GrafanaImage"
$argv = @('build') + $CommonArgs + @('-t', $GrafanaImage, '-f', 'images/monitoring/grafana.Dockerfile', 'images/monitoring')
$code = & $BuildJob $EnginePath $Root $argv (Join-Path $LogRoot 'grafana.log')
if ($code -ne 0) { Show-Failure 'grafana'; exit 1 }

Write-Host "== готово: $Image, $EgressImage, $GrafanaImage"
