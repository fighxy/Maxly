#!/usr/bin/env bash
# Собирает ffmpeg под LGPL для установщика из исходников ffmpeg.lock: без --enable-gpl, без
# --enable-nonfree, без libx264/x265 и без libopenh264. Сжатие H.264 для кружков — только
# системные кодировщики: Media Foundation (h264_mf) на Windows, VideoToolbox на macOS,
# VA-API на Linux. Opus — статический libopus (BSD).
#
#   bash scripts/build-ffmpeg.sh linux-x64      # на Linux (нужны libva-dev, nasm, pkg-config)
#   bash scripts/build-ffmpeg.sh windows-x64    # на Linux через mingw-w64 (кросс-сборка)
#   bash scripts/build-ffmpeg.sh macos-arm64    # на macOS (Xcode CLT, pkg-config)
#   bash scripts/build-ffmpeg.sh macos-x64      # на macOS Intel (ещё nasm)
#
# Результат — maxly-desktop/build/ffmpeg/<цель>/: ffmpeg(.exe), BUILDINFO.txt (версия и
# флаги configure) и licenses/. Его подхватывает задача Gradle prepareFfmpegBundle (или
# переменная MAXLY_FFMPEG_DIR с другой папкой). Архивы исходников кэшируются в
# ${MAXLY_FFMPEG_CACHE:-~/.cache/maxly-ffmpeg}.
set -euo pipefail

target="${1:-}"
desktop="$(cd "$(dirname "$0")/.." && pwd)"
lock="$desktop/ffmpeg.lock"
out="${2:-$desktop/build/ffmpeg/$target}"
work="$desktop/build/ffmpeg-work/$target"
cache="${MAXLY_FFMPEG_CACHE:-$HOME/.cache/maxly-ffmpeg}"
jobs="$( (nproc || sysctl -n hw.ncpu) 2>/dev/null || echo 2)"

value() { grep "^$1=" "$lock" | head -n 1 | cut -d= -f2- | tr -d '[:space:]'; }

case "$target" in
  linux-x64|windows-x64|macos-arm64|macos-x64) ;;
  *)
    echo "Цель: linux-x64, windows-x64, macos-arm64 или macos-x64" >&2
    exit 2
    ;;
esac

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Архив из ffmpeg.lock: скачать в кэш (если нет) и сверить SHA-256.
fetch() {
  local name="$1" url sum file
  url="$(value "$name.url")"
  sum="$(value "$name.sha256")"
  file="$cache/$(basename "$url")"
  mkdir -p "$cache"
  if [[ ! -f "$file" ]] || [[ "$(sha256 "$file")" != "$sum" ]]; then
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  if [[ "$(sha256 "$file")" != "$sum" ]]; then
    echo "SHA-256 $file не совпадает с ffmpeg.lock" >&2
    exit 1
  fi
  echo "$file"
}

ffmpeg_archive="$(fetch ffmpeg)"
opus_archive="$(fetch opus)"

rm -rf "$work"
mkdir -p "$work/src" "$work/prefix"
tar -xf "$ffmpeg_archive" -C "$work/src"
tar -xf "$opus_archive" -C "$work/src"
ffmpeg_src="$work/src/ffmpeg-$(value ffmpeg.version)"
opus_src="$work/src/opus-$(value opus.version)"
prefix="$work/prefix"

host_flags=()
ffmpeg_flags=()
cflags=""
ldflags=""
exe="ffmpeg"
strip_tool="strip"
case "$target" in
  linux-x64)
    pkg-config --exists libva libva-drm || { echo "Нужен libva-dev (VA-API)" >&2; exit 1; }
    ffmpeg_flags+=(--enable-vaapi --enable-pthreads)
    ;;
  windows-x64)
    cross="x86_64-w64-mingw32"
    host_flags+=(--host="$cross")
    ffmpeg_flags+=(--target-os=mingw32 --arch=x86_64 --cross-prefix="$cross-" --enable-mediafoundation --enable-d3d11va --enable-dxva2 --enable-w32threads --disable-indev=vfwcap)
    # Без libgcc и winpthread рядом: exe не тянет DLL MinGW. Media Foundation ffmpeg грузит сам при
    # первом h264_mf: в Windows N без Media Feature Pack ffmpeg запускается, не сжимает только H.264.
    # vfwcap (AVICAP32.dll) не нужен: камеру кружка даёт webrtc-java.
    ldflags="-static -static-libgcc"
    exe="ffmpeg.exe"
    strip_tool="$cross-strip"
    ;;
  macos-*)
    export MACOSX_DEPLOYMENT_TARGET=12.0
    cflags="-mmacosx-version-min=12.0"
    ldflags="-mmacosx-version-min=12.0"
    ffmpeg_flags+=(--enable-videotoolbox --enable-audiotoolbox --enable-pthreads)
    ;;
esac
if ! command -v nasm >/dev/null && [[ "$target" != macos-arm64 ]]; then
  echo "Нет nasm: ffmpeg соберётся без ассемблерных оптимизаций x86" >&2
  ffmpeg_flags+=(--disable-x86asm)
fi

# libopus: статически, только кодек. Защита стека выключена: на mingw-w64 ей нужна libssp.
(
  cd "$opus_src"
  CFLAGS="-O2 $cflags" LDFLAGS="$ldflags" ./configure ${host_flags[@]+"${host_flags[@]}"} --prefix="$prefix" \
    --disable-shared --enable-static --with-pic --disable-doc --disable-extra-programs --disable-stack-protector
  make -j"$jobs"
  make install
)

export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
# Кросс-сборке — только свои .pc: библиотеки хоста под Windows не годятся.
[[ "$target" == windows-* ]] && export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
configure_flags=(
  --prefix="$prefix"
  --pkg-config=pkg-config
  --pkg-config-flags=--static
  # Только явно названные внешние библиотеки: в сборку не попадёт найденное в системе (x264 из brew и т. п.).
  --disable-autodetect
  --disable-debug --disable-doc --disable-ffplay --disable-ffprobe
  --disable-shared --enable-static
  --enable-libopus
  ${ffmpeg_flags[@]+"${ffmpeg_flags[@]}"}
  --extra-cflags="-I$prefix/include $cflags"
  --extra-ldflags="-L$prefix/lib $ldflags"
)
(
  cd "$ffmpeg_src"
  ./configure "${configure_flags[@]}"
  # Лицензия сборки: только LGPL, ничего несвободного и никакого H.264-кодировщика в составе.
  for flag in CONFIG_GPL CONFIG_NONFREE CONFIG_LIBX264 CONFIG_LIBX265 CONFIG_LIBOPENH264; do
    if ! grep -q "^#define $flag 0" config.h; then
      echo "$flag включён: такая сборка не годится для установщика" >&2
      exit 1
    fi
  done
  make -j"$jobs"
  make install
)

rm -rf "$out"
mkdir -p "$out/licenses"
cp "$prefix/bin/$exe" "$out/$exe"
"$strip_tool" "$out/$exe" 2>/dev/null || true
chmod 755 "$out/$exe"
cp "$ffmpeg_src/COPYING.LGPLv2.1" "$out/licenses/ffmpeg-COPYING.LGPLv2.1.txt"
cp "$ffmpeg_src/LICENSE.md" "$out/licenses/ffmpeg-LICENSE.md"
cp "$opus_src/COPYING" "$out/licenses/opus-COPYING.txt"
configuration="$(sed -n 's/^#define FFMPEG_CONFIGURATION "\(.*\)"$/\1/p' "$ffmpeg_src/config.h")"
license="$(sed -n 's/^#define FFMPEG_LICENSE "\(.*\)"$/\1/p' "$ffmpeg_src/config.h")"
cat > "$out/BUILDINFO.txt" <<INFO
target=$target
ffmpeg.version=$(value ffmpeg.version)
ffmpeg.source=$(value ffmpeg.url)
ffmpeg.sha256=$(value ffmpeg.sha256)
opus.version=$(value opus.version)
opus.source=$(value opus.url)
opus.sha256=$(value opus.sha256)
license=$license
configuration=$configuration
INFO
echo "ffmpeg для $target: $out/$exe ($license)"
cat "$out/BUILDINFO.txt"
