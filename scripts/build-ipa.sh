#!/usr/bin/env bash
# Неподписанный Maxly.ipa для iPhone, на Mac с Xcode и JDK 17 — то же, что делает CI.
#
#   bash scripts/build-ipa.sh                                   # ядро по core.lock с GitHub
#   MAX_KMP_CORE_DIR=~/src/maxly-core bash scripts/build-ipa.sh   # ядро из локальной папки
#   SKIP_CORE=1 bash scripts/build-ipa.sh                       # ядро уже лежит в Vendor/
#
# Готовый файл: build/Maxly.ipa. Подписать его можно своим сертификатом
# (Sideloadly, AltStore, eSign и т. п.) и поставить на устройство.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Собрать .ipa можно только на macOS с Xcode." >&2
  exit 1
fi

if [[ -z "${SKIP_CORE:-}" ]]; then
  bash scripts/fetch-core.sh
fi
if [[ ! -d maxly-ios/Vendor/MaxlyCore.xcframework ]]; then
  echo "Нет maxly-ios/Vendor/MaxlyCore.xcframework: запустите без SKIP_CORE." >&2
  exit 1
fi

xcodebuild -project maxly-ios/Orbitle.xcodeproj -scheme Orbitle -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/device ARCHS=arm64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

app="build/device/Build/Products/Release-iphoneos/Maxly.app"
if [[ ! -d "$app" ]]; then
  echo "Xcode не положил $app" >&2
  exit 1
fi

rm -rf build/ipa build/Maxly.ipa
mkdir -p build/ipa/Payload
cp -R "$app" build/ipa/Payload/
(cd build/ipa && zip -qry ../Maxly.ipa Payload)
python3 scripts/validate-ipa.py build/Maxly.ipa
rm -rf build/ipa
echo "Готово: $root/build/Maxly.ipa ($(du -h build/Maxly.ipa | cut -f1))"
