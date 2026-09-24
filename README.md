<div align="center">

# 🛩️ Tweakpilot

**Your tweaks, your stats and your quick actions in one small panel on your SpringBoard.**

![iOS](https://img.shields.io/badge/iOS-18.0%20–%2026.x-000000?style=for-the-badge&logo=apple&logoColor=white)
![roothide](https://img.shields.io/badge/scheme-roothide-7B61FF?style=for-the-badge)
![arch](https://img.shields.io/badge/arch-arm64%20%7C%20arm64e-2EA44F?style=for-the-badge)
![build](https://img.shields.io/github/actions/workflow/status/xsxs18-dev/Tweakpilot/build.yml?style=for-the-badge&label=build)

</div>

---

## What it looks like

```
Installed Tweaks
────────────────────
● Crane               ON
● Choicy              ON
● AppData             ON
● CopyLog        OFF

Performance
────────────────────
RAM       3.2 GB
CPU       18%
Battery   87%

Quick Actions
────────────────────
[ Respring ] [ Restart Injection ]
```

A small bubble floats at the edge of your screen. Tap it and the panel opens. Tap anywhere outside the panel to close it again.

## Features

| | |
|---|---|
| 🔌 **Turn tweaks on and off** | Tap a tweak in the list to turn it on or off. That's it. The change shows up in orange with `↻` until you respring. |
| 📏 **Resizable panel** | Pinch the panel with two fingers, or drag the `⤡` grip in the bottom-right corner. Tweakpilot remembers the size you pick. |
| 📊 **Live stats** | Used RAM, CPU load and battery level, refreshed every 1.5 seconds while the panel is open. |
| ⚡ **Quick actions** | **Respring** restarts SpringBoard. **Restart Injection** does a userspace reboot, so every app reloads with your current tweaks. |
| 🫧 **Floating bubble** | Drag it anywhere. It snaps to the nearest edge and stays where you left it. |
| 🧊 **Liquid Glass** | Uses the real Liquid Glass material on iOS 26 and falls back to the system blur on iOS 18–25. |
| 🔒 **Lock screen safe** | The bubble and panel are hidden while the device is locked. |

## Installation

1. Open the [**Releases**](../../releases) page.
2. Download the newest `Tweakpilot_…_roothide.deb`.
3. Install it with Sileo or Zebra, or run `dpkg -i` in a terminal.
4. Respring.

Every push to `main` is built automatically and published as its own release.

## Requirements

- iOS 18.0 to 26.x
- A roothide jailbreak
- ElleKit or another substrate-compatible hooking library

## How turning tweaks off works

Every tweak lives as a `.dylib` in `jbroot/Library/MobileSubstrate/DynamicLibraries`. When you turn a tweak off, Tweakpilot renames `Name.dylib` to `Name.dylib.disabled`, so the tweak isn't loaded after the next respring. Turning it back on renames it again. Nothing gets deleted.

SpringBoard isn't allowed to rename those files itself, so Tweakpilot ships a tiny helper called `tpctl` at `jbroot/usr/libexec/tweakpilot/tpctl`. The helper is kept as small as possible:

- It only knows `enable`, `disable`, `respring` and `userspace`.
- Only `mobile` and `root` can run it.
- It only accepts plain tweak names. Paths, `..` and hidden files are refused.
- It only renames regular files inside the tweak folder. Symlinks are refused.
- It won't turn off Tweakpilot itself.

## Building it yourself

The GitHub Action handles everything. If you'd rather build on a Mac:

```sh
git clone --recursive https://github.com/roothide/theos.git ~/theos
export THEOS=~/theos
gmake package FINALPACKAGE=1
```

The `.deb` ends up in `packages/`.

## Project structure

```
Tweak.x                      hooks SpringBoard and sets up the overlay
Sources/TPOverlay.m          the floating bubble and window
Sources/TPPanelViewController.m   the panel itself
Sources/TPTweakStore.m       reads the tweak list and talks to tpctl
Sources/TPStats.m            RAM, CPU and battery
tpctl/main.c                 the helper
```

## Feedback

Found a bug or have an idea? Open an issue. Screenshots help a lot.

<div align="center">
<sub>Made by xsxs18</sub>
</div>
