#!/usr/bin/env bash
# Собирает статический MaxlyCore.xcframework из ревизии orbitle-ios/core.lock.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
lock="$root/orbitle-ios/core.lock"
revision="$(grep '^revision=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"
repository="$(grep '^repository=' "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]')"

if [[ -z "$revision" || -z "$repository" ]]; then
  echo "В core.lock нужны строки revision= и repository=" >&2
  exit 1
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

mkdir -p "$root/orbitle-ios/Vendor"
rm -rf "$root/orbitle-ios/Vendor/MaxlyCore.xcframework"
cp -R "$framework" "$root/orbitle-ios/Vendor/MaxlyCore.xcframework"
echo "MaxlyCore.xcframework из $revision лежит в orbitle-ios/Vendor."
