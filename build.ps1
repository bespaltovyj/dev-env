# Сборка agent-box: downloader -> компоненты (параллельно) -> итоговый образ.
#
#   .\build.ps1                                       # всё
#   .\build.ps1 -BuildArgs 'GO_VERSION=1.27.3'        # аргументы передаются во все сборки
#   .\build.ps1 -Engine docker -Jobs 8
[CmdletBinding()]
param(
    [string]   $Engine    = 'podman',
    [string]   $Prefix    = 'localhost/agent-box',
    [string]   $Image     = 'localhost/agent-box:latest',
    [string]   $EgressImage = 'localhost/agent-box-egress:latest',
    [int]      $Jobs      = 4,
    [string]   $LogDir    = '.build-logs',
    [string[]] $BuildArgs = @()
)

# Continue: в PowerShell 5.1 перенаправленный stderr podman при Stop прерывает скрипт;
# результат сборок проверяется по $LASTEXITCODE
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

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
    $argv = @('build') + $CommonArgs + @('--build-arg', "DOWNLOADER_IMAGE=$Prefix/downloader:latest")
    if ($Deps.ContainsKey($Name)) { $argv += Get-ContextArgs $Deps[$Name] }
    # stages/<группа>/<name>.Dockerfile или stages/<name>.Dockerfile
    $file = Get-ChildItem -Path stages -Recurse -Filter "$Name.Dockerfile" | Select-Object -First 1
    if (-not $file) { throw "нет stages/**/$Name.Dockerfile" }
    $rel = $file.FullName.Substring($PSScriptRoot.Length + 1).Replace('\', '/')
    $argv += @('-t', "$Prefix/${Name}:latest", '-f', $rel, 'stages')
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
            -ArgumentList $EnginePath, $PSScriptRoot, (Get-ComponentArgs $n), (Join-Path $LogRoot "$n.log")
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

Write-Host '== downloader'
$code = & $BuildJob $EnginePath $PSScriptRoot (Get-ComponentArgs 'downloader') (Join-Path $LogRoot 'downloader.log')
if ($code -ne 0) { Show-Failure 'downloader'; exit 1 }

Write-Host '== компоненты'
Invoke-Wave $Wave1
Invoke-Wave $Wave2

Write-Host "== $Image"
$argv = @('build') + $CommonArgs + (Get-ContextArgs ($Wave1 + $Wave2)) + @('-t', $Image, '-f', 'Dockerfile', '.')
& $EnginePath @argv 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath (Join-Path $LogRoot 'final.log')
if ($LASTEXITCODE -ne 0) { exit 1 }

# Прокси для выхода agent в интернет (allowlist.txt встроен в образ)
Write-Host "== $EgressImage"
$argv = @('build') + $CommonArgs + @('-t', $EgressImage, '-f', 'egress/Dockerfile', 'egress')
$code = & $BuildJob $EnginePath $PSScriptRoot $argv (Join-Path $LogRoot 'egress.log')
if ($code -ne 0) { Show-Failure 'egress'; exit 1 }

Write-Host "== готово: $Image, $EgressImage"
