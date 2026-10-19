# FFmpeg in Maxly Desktop

The Maxly Desktop installers (`.msi`, `.dmg`, `.deb`) ship a separate, unmodified FFmpeg
command-line executable (`ffmpeg` / `ffmpeg.exe`) in the application resources. Maxly runs
it as a child process to decode video, GIFs (MP4), video notes and voice messages, and to
encode voice messages (Ogg/Opus) and video notes (MP4 H.264/AAC). Maxly does not link
against FFmpeg.

## License

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later
(`COPYING.LGPLv2.1.txt`). The bundled build is configured **without** `--enable-gpl`,
`--enable-version3` and `--enable-nonfree`; it contains no GPL or non-free components.
In particular it contains no libx264, libx265 or libopenh264. `scripts/build-ffmpeg.sh`
refuses to produce a build where `CONFIG_GPL`, `CONFIG_NONFREE`, `CONFIG_LIBX264`,
`CONFIG_LIBX265` or `CONFIG_LIBOPENH264` is enabled.

The executable is a separate file: you may replace it with your own FFmpeg build.

Statically linked into it:

| Component | Version | License | Source |
|---|---|---|---|
| FFmpeg | 9.0.2 | LGPL-2.1-or-later | https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz (SHA-256 `8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`) |
| libopus | 1.6.1 | BSD-3-Clause (`opus-COPYING.txt`) | https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz (SHA-256 `6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1`) |

Dynamically used system components (not shipped): Media Foundation (Windows),
VideoToolbox and AudioToolbox (macOS), libva / libva-drm (Linux, MIT).

## Build

Every installer's FFmpeg is built from the sources above by `maxly-desktop/scripts/build-ffmpeg.sh`
(pinned in `maxly-desktop/ffmpeg.lock`) in the `Desktop` GitHub Actions workflow. No binaries are
committed. The exact `configure` line of each build is in `BUILDINFO.txt` next to the executable.
Common flags:

```
--pkg-config=pkg-config --pkg-config-flags=--static --disable-autodetect --disable-debug --disable-doc
--disable-ffplay --disable-ffprobe --disable-shared --enable-static --enable-libopus
```

Per platform:

| Installer | Target | Extra flags | H.264 encoder used for video notes |
|---|---|---|---|
| `.msi` | `windows-x64` (cross-built with mingw-w64) | `--target-os=mingw32 --arch=x86_64 --cross-prefix=x86_64-w64-mingw32- --enable-mediafoundation --enable-d3d11va --enable-dxva2 --enable-w32threads --disable-indev=vfwcap`, `-static -static-libgcc` | `h264_mf` (Media Foundation) |
| `.dmg` | `macos-arm64` | `--enable-videotoolbox --enable-audiotoolbox --enable-pthreads`, `-mmacosx-version-min=12.0` | `h264_videotoolbox` |
| `.deb` | `linux-x64` | `--enable-vaapi --enable-pthreads` | `h264_vaapi` |

H.264 decoding uses FFmpeg's own decoder and works everywhere. H.264 encoding uses only the
operating system's encoder; if none is available (for example Windows N/KN without the Media
Feature Pack, or Linux without a VA-API driver), Maxly says that video notes cannot be
recorded.

Source code of FFmpeg: https://ffmpeg.org/download.html, https://git.ffmpeg.org/ffmpeg.git
(tag `n9.0.2`). On request we provide the exact sources and build scripts used for any
installer we distributed.
