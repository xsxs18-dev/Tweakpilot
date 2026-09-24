# Tweakpilot

A little floating panel for your SpringBoard that shows all your tweaks, lets you turn them on and off with a tap, and has respring / userspace reboot buttons right there.

I made this because I kept opening Sileo just to disable one tweak and check if it was the thing breaking my phone. Now it's one tap.

Built for **roothide**, iOS 18 to 26, arm64 and arm64e.

![build](https://img.shields.io/github/actions/workflow/status/xsxs18-dev/Tweakpilot/build.yml?label=build)

## What you get

```
Installed Tweaks
────────────────────
● Crane               ON
● Choicy              ON
● AppData             ON
● CopyLog             OFF

Performance
────────────────────
RAM       3.2 GB
CPU       18%
Battery   87%

Quick Actions
────────────────────
[ Respring ] [ Restart Injection ]
```

There's a small bubble on the side of your screen. Tap it and the panel pops up. Tap outside the panel to close it.

- **Tap a tweak to turn it on or off.** It turns orange until you respring, so you know something's pending.
- **Resize the panel** by pinching it, or by dragging the little arrow in the bottom right corner. It remembers the size.
- **RAM, CPU and battery** update live while the panel is open.
- **Respring** does what you'd expect. **Restart Injection** does a userspace reboot, so every app reloads with your current tweaks.
- **Move the bubble** wherever you want. It snaps to the edge and stays there.
- On iOS 26 it uses the new Liquid Glass look. On older versions you get the normal blur.
- It hides itself on the lock screen, so nobody can mess with your tweaks while your phone is locked.

## Installing

Grab the newest `.deb` from [Releases](../../releases) and install it with Sileo, Zebra or `dpkg -i`. Then respring.

Every push to `main` gets built and released automatically, so the newest release is always the latest code.

## How the on/off thing works

Tweaks are just `.dylib` files in `jbroot/Library/MobileSubstrate/DynamicLibraries`. Turning one off renames `Name.dylib` to `Name.dylib.disabled`, and turning it on renames it back. Nothing gets deleted, and you can undo it any time.

SpringBoard isn't allowed to rename those files, so there's a small helper called `tpctl` that does it. I kept it as dumb as possible on purpose:

- it only does `enable`, `disable`, `respring` and `userspace`
- only `mobile` and `root` can run it
- it only accepts plain tweak names: no paths, no `..`, no symlinks
- it won't disable Tweakpilot itself

## Building

GitHub Actions builds everything. If you want to build it on your Mac:

```sh
git clone --recursive https://github.com/roothide/theos.git ~/theos
export THEOS=~/theos
gmake package FINALPACKAGE=1
```

## Heads up

This is still early. I haven't been able to test it on every device and iOS version, so if something's off, open an issue with your device, iOS version and jailbreak and I'll take a look.

Ideas are welcome too.

— xsxs18
