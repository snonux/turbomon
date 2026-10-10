# Shizuku and root

TurboMon works fully as a normal app. Android hides some system data from
normal apps, though, and two optional routes unlock it:

- [**Shizuku**](https://shizuku.rikka.app/) runs a helper with `adb shell`
  rights. No root needed: start it once after each reboot with wireless
  debugging (Android 11+) or `adb`.
- **Root** (`su`, e.g. Magisk or KernelSU).

Settings, *Elevated access* chooses which one TurboMon uses: *Automatic*
(Shizuku if it is running and allowed, else root if granted, else normal),
*Normal app only*, *Shizuku* or *Root*. The Top tab shows the level in use.

## What each level shows

| Data | Normal app | Shizuku | Root |
|---|---|---|---|
| CPU total and per core | Frequency as a proxy | Real usage from `/proc/stat` | Real usage |
| Process list | TurboMon only | All processes | All processes |
| GPU busy | Some devices | Most devices | Yes |
| Thermal zones | Thermal status and headroom; zones on some devices | All zones | All zones |
| Disk I/O | Some devices | Yes | Yes |
| Per-app battery (batterystats) | No | Yes | Yes |
| RAM, battery, network, storage, Wi-Fi, Bluetooth | Yes | Yes | Yes |

"Some devices" means it depends on the vendor's SELinux policy; TurboMon
tries the normal route first and says when a value is hidden.

## How it works

Privileged reads are plain shell commands (`cat /proc/stat`, `ps`,
`cat /sys/class/thermal/...`, `dumpsys batterystats`). TurboMon batches each
refresh into one command, so Shizuku or `su` is called once per refresh, not
once per file. Nothing is ever written with elevated rights.

With root, your root manager asks once whether to grant TurboMon. With
Shizuku, TurboMon asks for Shizuku's permission the first time you choose it.
If Shizuku stops (for example after a reboot), TurboMon falls back to normal
mode and the Top tab says so.
