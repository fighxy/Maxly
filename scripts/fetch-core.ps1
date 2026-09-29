# Клонирует max-kmp-core на ревизию из orbitl-ios/core.lock.
# XCFramework на Windows не собирается: для него нужен macOS, JDK 17 и Xcode.
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$lockPath = Join-Path $root "orbitl-ios\core.lock"
$revision = $null
$repository = $null
foreach ($line in Get-Content -Path $lockPath) {
    if ($line -like "revision=*") { $revision = $line.Substring("revision=".Length).Trim() }
    if ($line -like "repository=*") { $repository = $line.Substring("repository=".Length).Trim() }
}
if (-not $revision -or -not $repository) {
    throw "В core.lock нужны строки revision= и repository="
}

$dest = Join-Path $root ".build\max-kmp-core"
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) {
    $candidate = Join-Path $env:LOCALAPPDATA "grok\git\2.55.0.windows.5\cmd\git.exe"
    if (Test-Path $candidate) { $git = $candidate } else { throw "git не найден в PATH" }
}

function Invoke-CoreGit {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $prefix = @("-C", $dest)
    if ($env:MAX_KMP_CORE_TOKEN) {
        $prefix += @("-c", "http.extraheader=AUTHORIZATION: bearer $($env:MAX_KMP_CORE_TOKEN)")
    }
    & $git @prefix @GitArgs
    if ($LASTEXITCODE -ne 0) { throw "git завершился с кодом $LASTEXITCODE" }
}

Invoke-CoreGit init
Invoke-CoreGit remote add origin $repository
Invoke-CoreGit fetch --depth 1 origin $revision
Invoke-CoreGit checkout --detach FETCH_HEAD

Write-Host "Ядро $revision лежит в $dest."
Write-Host "MaxIos.xcframework на Windows не собирается. На macOS и в CI это делает scripts/fetch-core.sh."
