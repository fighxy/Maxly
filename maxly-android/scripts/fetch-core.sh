#!/usr/bin/env bash
# Собирает Android-библиотеки ядра (core и shared, .aar) из ревизии maxly-android/core.lock
# и кладёт их в maxly-android/vendor. Приложение подключает их как файлы, поэтому версии
# Gradle, AGP и Kotlin у приложения и ядра не обязаны совпадать.
set -euo pipefail

# root — папка maxly-android.
root="$(cd "$(dirname "$0")/.." && pwd)"
lock="$root/core.lock"
revision="$(grep '^revision=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"
repository="$(grep '^repository=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"

if [[ -z "$revision" || -z "$repository" ]]; then
  echo "В core.lock нужны строки revision= и repository=" >&2
  exit 1
fi

# Локальная копия ядра вместо GitHub: MAX_KMP_CORE_DIR=~/src/maxly-core bash maxly-android/scripts/fetch-core.sh
# Собирается то, что лежит в этой папке сейчас, ревизия из core.lock не проверяется.
if [[ -n "${MAX_KMP_CORE_DIR:-}" ]]; then
  dest="$(cd "$MAX_KMP_CORE_DIR" && pwd)"
  echo "Ядро из локальной папки $dest ($(git -C "$dest" rev-parse --short HEAD 2>/dev/null || echo 'без git')), core.lock: $revision"
else
  dest="$root/.build/max-kmp-core"
  current="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$current" != "$revision" ]]; then
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
  fi
fi

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk" ]]; then
  echo "Нужен Android SDK: задайте ANDROID_HOME" >&2
  exit 1
fi
if [[ ! -f "$dest/local.properties" ]] || ! grep -q '^sdk.dir=' "$dest/local.properties"; then
  echo "sdk.dir=$sdk" >> "$dest/local.properties"
fi

chmod +x "$dest/gradlew"
# Только Android-варианты: цели iOS на Linux Gradle пропускает сам.
( cd "$dest" && ./gradlew :core:assembleRelease :shared:assembleRelease --no-daemon --console=plain -q )

vendor="$root/vendor"
mkdir -p "$vendor"
cp "$dest/core/build/outputs/aar/core-release.aar" "$vendor/max-core.aar"
cp "$dest/shared/build/outputs/aar/shared-release.aar" "$vendor/max-shared.aar"
printf '%s\n' "$revision" > "$vendor/REVISION"
echo "Ядро $revision: maxly-android/vendor/max-core.aar, max-shared.aar"
