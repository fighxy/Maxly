#!/usr/bin/env bash
# Собирает статический MaxlyCore.xcframework из ревизии maxly-ios/core.lock.
#
# revision= — коммит, ветка или `latest`. `latest` — последний коммит `main` ядра, на котором
# прошёл его CI (workflow `ios-core.yml`); если GitHub API недоступен — просто `main`.
# Пока CI только что влитого ядра идёт, `latest` — ещё прежний коммит: приложению, которому
# уже нужно новое ядро (или ядро из незалитой ветки), коммит вписывается в core.lock явно.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
lock="$root/maxly-ios/core.lock"
revision="$(grep '^revision=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"
repository="$(grep '^repository=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"

if [[ -z "$revision" || -z "$repository" ]]; then
  echo "В core.lock нужны строки revision= и repository=" >&2
  exit 1
fi

# Последний зелёный коммит `main` ядра: прогоны `ios-core.yml` на `main` со статусом success.
latest_green() {
  local slug="${repository#https://github.com/}"
  slug="${slug%.git}"
  local auth=()
  if [[ -n "${MAX_KMP_CORE_TOKEN:-}" ]]; then auth=(-H "Authorization: Bearer ${MAX_KMP_CORE_TOKEN}"); fi
  curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${slug}/actions/workflows/ios-core.yml/runs?branch=main&status=success&per_page=1" 2>/dev/null \
    | python3 -c 'import json, sys; runs = json.load(sys.stdin).get("workflow_runs") or []; print(runs[0]["head_sha"] if runs else "")' 2>/dev/null \
    || true
}

if [[ "$revision" == "latest" && -z "${MAX_KMP_CORE_DIR:-}" ]]; then
  green="$(latest_green)"
  if [[ -n "$green" ]]; then
    echo "Ядро: последний зелёный коммит main — $green"
    revision="$green"
  else
    echo "::warning::Не удалось узнать последний зелёный коммит ядра, берётся main."
    revision="main"
  fi
fi

# Локальная копия ядра вместо GitHub: MAX_KMP_CORE_DIR=~/src/maxly-core bash scripts/fetch-core.sh
# Собирается то, что лежит в этой папке сейчас, ревизия из core.lock не проверяется.
if [[ -n "${MAX_KMP_CORE_DIR:-}" ]]; then
  dest="$(cd "$MAX_KMP_CORE_DIR" && pwd)"
  echo "Ядро из локальной папки $dest ($(git -C "$dest" rev-parse --short HEAD 2>/dev/null || echo 'без git')), core.lock: $revision"
else
dest="$root/.build/max-kmp-core"
rm -rf "$dest"
mkdir -p "$dest"
git init "$dest" >/dev/null

core_git() {
  if [[ -n "${MAX_KMP_CORE_TOKEN:-}" ]]; then
    # Git по HTTPS принимает токен только как Basic-авторизацию, Bearer GitHub отклоняет.
    local basic
    basic="$(printf 'x-access-token:%s' "$MAX_KMP_CORE_TOKEN" | base64 | tr -d '\n')"
    git -C "$dest" -c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${basic}" "$@"
  else
    git -C "$dest" "$@"
  fi
}

core_git remote add origin "$repository"
core_git fetch --depth 1 origin "$revision"
git -C "$dest" checkout --detach FETCH_HEAD
revision="$(git -C "$dest" rev-parse HEAD)"
echo "Ядро $repository @ $revision"
# В сводке прогона видно, из какого коммита ядра собрано приложение.
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "Ядро: [\`${revision:0:7}\`](${repository%.git}/commit/$revision)" >> "$GITHUB_STEP_SUMMARY"
fi
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Ядро $revision лежит в $dest."
  echo "MaxlyCore.xcframework собирается только на macOS с JDK 17 и Xcode."
  exit 0
fi

if ! command -v java >/dev/null 2>&1; then
  echo "Нужен JDK 17, чтобы собрать XCFramework." >&2
  exit 1
fi

chmod +x "$dest/gradlew"
( cd "$dest" && ./gradlew :ios:assembleMaxlyCoreReleaseXCFramework --no-daemon --stacktrace )

framework="$dest/ios/build/XCFrameworks/release/MaxlyCore.xcframework"
if [[ ! -d "$framework" ]]; then
  echo "Gradle не положил $framework" >&2
  exit 1
fi

mkdir -p "$root/maxly-ios/Vendor"
rm -rf "$root/maxly-ios/Vendor/MaxlyCore.xcframework"
cp -R "$framework" "$root/maxly-ios/Vendor/MaxlyCore.xcframework"
echo "MaxlyCore.xcframework из $revision лежит в maxly-ios/Vendor."
