# Tweakpilot

A floating control panel for jailbroken iOS 18–26 that lives on your SpringBoard, built for the **roothide** layout.

Tap the small floating bubble and you get:

```
Installed Tweaks
────────────────────
● CommandBar          ON
● PerAppOS            ON
● SmartPaste          ON
● BatteryBrain        ON

Performance
────────────────────
RAM       3.2 GB
CPU       18%
Battery   87%

Quick Actions
────────────────────
[ Respring ] [ Restart Injection ]
```

## Features

- **Installed Tweaks** lists every tweak in `jbroot/Library/MobileSubstrate/DynamicLibraries`. Tap a row to switch it ON or OFF. Tweakpilot renames `Name.dylib` to `Name.dylib.disabled` (and back), so the tweak stops loading after the next respring. Rows you changed show an orange `↻` until you respring.
- **Performance** shows used RAM, total CPU load and battery level. The values refresh every 1.5 seconds while the panel is open.
- **Quick Actions**
  - **Respring** restarts SpringBoard (`killall -9 backboardd`).
  - **Restart Injection** does a userspace reboot (`launchctl reboot userspace`), so every process gets re-injected with your current set of tweaks.
- A draggable bubble that snaps to the screen edge and remembers where you left it.
- On iOS 26 the panel uses Liquid Glass (`UIGlassEffect`). On iOS 18–25 it falls back to the system material blur.
- The panel is hidden while the device is locked, so nobody can toggle tweaks or reboot from the lock screen.

## Compatibility

| | |
|---|---|
| iOS | 18.0 – 26.x |
| Package scheme | roothide (`iphoneos-arm64e`) |
| Architectures | arm64, arm64e |
| Injected into | SpringBoard only |

> **Note:** Tweakpilot is built and packaged for roothide on iOS 18–26. It can only run on a device where a roothide-compatible jailbreak exists for that iOS version.

## Project layout

```
Tweak.x                      SpringBoard hook; installs the overlay after launch
Sources/
  TPOverlay.m                overlay window, floating bubble, lock-state handling
  TPPanelViewController.m    the panel UI
  TPTweakStore.m             lists tweaks and calls the helper
  TPStats.m                  RAM / CPU / battery via Mach and UIDevice
  TPRoot.h                   roothide jbroot() wrapper
tpctl/                       small setuid root helper (see Security)
.github/workflows/build.yml  cloud build with roothide Theos
```

## Building

Builds run **only in the cloud** via GitHub Actions (see `.github/workflows/build.yml`). Every push builds the package on a macOS runner with [roothide/theos](https://github.com/roothide/theos) and uploads the `.deb` as the `Tweakpilot-roothide` artifact.

1. Push to any branch, or start the **Build** workflow manually from the Actions tab.
2. Download the `Tweakpilot-roothide` artifact from the finished run.
3. Install the `.deb` with Sileo or Zebra, or run `dpkg -i`, then respring.

If you want to build on a Mac yourself:

```sh
export THEOS=~/theos   # roothide fork of Theos
gmake package FINALPACKAGE=1
```

## Security

SpringBoard runs as `mobile` and cannot rename root-owned files. Tweakpilot therefore ships a small helper, `tpctl`, installed setuid root at `jbroot/usr/libexec/tweakpilot/tpctl`. The helper is kept deliberately narrow:

- It accepts exactly four commands: `enable <name>`, `disable <name>`, `respring`, `userspace`.
- Only the users `mobile` (501) and `root` may run it.
- Tweak names must be plain file names: no `/`, no `..`, no leading dot, and only `[A-Za-z0-9 ._+-]`.
- It only renames regular files (checked with `lstat`, so symlinks are rejected) inside the DynamicLibraries folder.
- It refuses to disable Tweakpilot itself.

## Development rules

This project follows the rules in `CLAUDE_SICHERHEIT.md` in the parent project folder:

- Only files inside the project folder are read, created or changed.
- No `rm` outside the project folder, and no changes to system folders.
- No local iOS builds on Linux. All builds run in GitHub Actions.
- Changes are committed with short English commit messages (for example `feat: add tweak toggle`) and pushed, which starts the cloud build.
- If a GitHub Actions build fails, the cause is read from the log and fixed in this folder before pushing again.

## License

Private project. All rights reserved.
