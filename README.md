# mSILENCE

[Français](README.fr.md)

## About

mSILENCE is a personal, independent per-app firewall and network monitor for macOS, inspired by [Radio Silence](https://radiosilenceapp.com/). It is not affiliated with Radio Silence or its author, and contains none of its code. © 2026 Starbudweiser, MIT license.

## Features

- **Block any app from the network**: drag and drop an app, or pick it in a list. Its helpers and child processes are blocked with it; traffic to and from this Mac stays allowed.
- **Invisible and always on**: a network content filter (system extension) runs in the background, with no pop-up and no menu bar icon, even when mSILENCE is closed.
- **Live network monitor**: every outgoing connection by app, with a one-click block.
- **Import from Radio Silence**: brings in its list of blocked apps (never its license or other settings, and nothing is changed in Radio Silence). Done automatically the first time mSILENCE opens.
- **Automatic updates** from GitHub releases (can be turned off).
- **Four languages** (French, English, Spanish, Italian), picked from the system language. Dark, flat interface.

## Build

Requires macOS 14+, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
./build_app.sh    # builds mSILENCE.app (Developer ID), installs it in /Applications (macOS only activates a system extension from there)
```

A network content filter needs Apple-signed entitlements, so the build is signed with a Developer ID profile that includes the *Network Extensions* capability (team `35KLMK53PN`, to be changed in `project.yml`, `build_app.sh` and `scripts/ExportOptions.plist`). `NO_INSTALL=1` skips the installation.

On first launch, click **Install the network filter**, then allow mSILENCE in *System Settings › General › Login Items & Extensions › Network Extensions*.

Data: `~/Library/Application Support/mSILENCE/rules.json` (`MSILENCE_DATA_DIR` for tests). Offscreen checks, without opening any window: `mSILENCE --capture out.png [--tab monitor|settings] [--demo]`, `--capture-about out.png`, `--import-radio-silence`.
