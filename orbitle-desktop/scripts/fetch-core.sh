#!/usr/bin/env bash
# Кладёт исходники maxly-core ревизии из orbitle-desktop/core.lock в .build/max-kmp-core
# в корне репозитория: десктоп собирает ядро из них сам. Для Windows то же делает
# scripts/fetch-core.ps1.
set -euo pipefail

# root — корень репозитория.
root="$(cd "$(dirname "$0")/../.." && pwd)"
lock="$root/orbitle-desktop/core.lock"
revision="$(grep '^revision=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"
repository="$(grep '^repository=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"

if [[ -z "$revision" || -z "$repository" ]]; then
  echo "В core.lock нужны строки revision= и repository=" >&2
  exit 1
fi

# Локальная копия ядра вместо GitHub: MAX_KMP_CORE_DIR=~/src/maxly-core ./gradlew build
# Сборка берёт исходники прямо из этой папки, скачивать нечего.
if [[ -n "${MAX_KMP_CORE_DIR:-}" ]]; then
  echo "Ядро из локальной папки $MAX_KMP_CORE_DIR, core.lock: $revision. Скачивание не нужно."
  exit 0
fi

dest="$root/.build/max-kmp-core"
current="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
if [[ "$current" == "$revision" ]]; then
  echo "Ядро $revision уже лежит в $dest."
  exit 0
fi

rm -rf "$dest"
mkdir -p "$dest"
git init -q "$dest"

core_git() {
  if [[ -n "${MAX_KMP_CORE_TOKEN:-}" ]]; then
    # Git по HTTPS принимает токен только как Basic-авторизацию.
    local basic
    basic="$(printf 'x-access-token:%s' "$MAX_KMP_CORE_TOKEN" | base64 | tr -d '\n')"
    git -C "$dest" -c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${basic}" "$@"
  else
    git -C "$dest" "$@"
  fi
}

core_git remote add origin "$repository"
core_git fetch -q --depth 1 origin "$revision"
git -C "$dest" checkout -q --detach FETCH_HEAD
echo "Ядро $revision лежит в $dest."
