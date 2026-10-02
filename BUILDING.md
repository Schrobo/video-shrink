# Building and packaging

Use Flutter 3.44.7, pinned in `mise.toml`, with the committed `pubspec.lock`.
Build each desktop target on its own operating system:

| System | Build tools | Command |
| --- | --- | --- |
| macOS | Full Xcode | `flutter build macos --release` |
| Windows | Visual Studio C++ desktop tools | `flutter build windows --release` |
| Linux | Clang, CMake, Ninja, pkg-config, GTK 3 and LZMA development libraries | `flutter build linux --release` |

The GitHub Actions workflow compiles and archives development apps. Its artifacts
expire after three days. It does not publish releases, notarize apps or bundle
FFmpeg. macOS builds target Apple Silicon; Windows and Linux builds target x64.

## Video processing

The desktop adapter calls FFmpeg and FFprobe locally, without a shell. It creates
MP4 files using H.264, YUV 4:2:0 and AAC, capped at 30 fps. Resolution and bitrate
depend on duration, aspect ratio, the selected size target and text preservation.
It preserves portrait and landscape orientation, avoids upscaling, handles
rotation metadata and anamorphic pixels, and uses even output dimensions.

HDR input requires `zscale` and `tonemap`; otherwise the app explains that the
installed toolset cannot process it. Very long videos prompt for a larger profile
or a shorter video. Automatic splitting is not implemented.

Outputs are checked for size, format, duration and successful decoding. Up to
three attempts lower the bitrate when necessary. Cancellation only removes
temporary files created by the current operation. Existing outputs are preserved.

## FFmpeg bundles

The app looks for both tools in these paths before checking development paths:

| Platform | Bundle location |
| --- | --- |
| macOS | `Contents/Resources/ffmpeg/` |
| Windows | `ffmpeg/` beside the EXE |
| Linux | `lib/ffmpeg/` inside the bundle |

`VIDEO_SHRINK_FFMPEG_DIR` can explicitly select a local tool directory. For local
development, Homebrew paths on macOS and `PATH` are also checked.

`dart run tool/bundle_ffmpeg.dart <source> <destination>` copies an explicitly
supplied self-contained toolset. It requires both executables, `LICENSE.txt`,
`SOURCES.txt`, H.264/AAC encoders and the HDR filters. It does not download tools
or make dynamically linked Homebrew binaries portable. Include the license and
corresponding sources required by the exact FFmpeg build before distribution.

macOS App Sandbox remains enabled. The app asks for an output folder so it can
write there. Bundle FFmpeg and FFprobe with inherited sandbox entitlements from
`tool/ffmpeg-inherit.entitlements`, then sign the complete app. A system FFmpeg
installation alone is not a supported packaged macOS distribution.

Before a distribution release, test on a clean machine with no installed FFmpeg
and complete platform signing and macOS notarization.

## Assets

`swift tool/generate_icons.swift .` regenerates the app icons on macOS.
`docs/cover.svg` is the vector README cover. The animation under `media/` uses
only drawn UI layers and a cursor, with example file sizes. Its dependencies
are separate from the desktop application.
