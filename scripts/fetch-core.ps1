# Кладёт исходники max-kmp-core ревизии из maxly-desktop/core.lock в .build\max-kmp-core
# в корне репозитория: десктоп собирает ядро из них сам. Для Linux и macOS то же делает
# maxly-desktop/scripts/fetch-core.sh.
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$lockPath = Join-Path (Join-Path $root "maxly-desktop") "core.lock"
$revision = $null
$repository = $null
foreach ($line in Get-Content -Path $lockPath) {
    if ($line -like "revision=*") { $revision = $line.Substring("revision=".Length).Trim() }
    if ($line -like "repository=*") { $repository = $line.Substring("repository=".Length).Trim() }
}
if (-not $revision -or -not $repository) {
    throw "В core.lock нужны строки revision= и repository="
}

# Локальная копия ядра вместо GitHub: $env:MAX_KMP_CORE_DIR = "C:\src\max-kmp-core"; .\gradlew.bat build
# Сборка берёт исходники прямо из этой папки, скачивать нечего.
if ($env:MAX_KMP_CORE_DIR) {
    Write-Host "Ядро из локальной папки $($env:MAX_KMP_CORE_DIR), core.lock: $revision. Скачивание не нужно."
    exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git не найден в PATH"
}

$dest = Join-Path (Join-Path $root ".build") "max-kmp-core"
if (Test-Path (Join-Path $dest ".git")) {
    $current = (& git -C $dest rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $current -eq $revision) {
        Write-Host "Ядро $revision уже лежит в $dest."
        exit 0
    }
}
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force -Path $dest | Out-Null

# Аргументы git передаются как есть через $args.
function Invoke-CoreGit {
    $prefix = @("-C", $dest)
    if ($env:MAX_KMP_CORE_TOKEN) {
        # Git по HTTPS принимает токен только как Basic-авторизацию.
        $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$($env:MAX_KMP_CORE_TOKEN)"))
        $prefix += @("-c", "http.https://github.com/.extraheader=AUTHORIZATION: basic $basic")
    }
    & git @prefix @args
    if ($LASTEXITCODE -ne 0) { throw "git завершился с кодом $LASTEXITCODE" }
}

Invoke-CoreGit init -q
Invoke-CoreGit remote add origin $repository
Invoke-CoreGit fetch -q --depth 1 origin $revision
Invoke-CoreGit checkout -q --detach FETCH_HEAD

Write-Host "Ядро $revision лежит в $dest."
