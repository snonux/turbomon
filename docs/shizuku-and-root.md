# Shizuku and root

TurboMon works as a normal app. Android hides some system data from normal
apps, though, and two optional routes unlock it:

- [**Shizuku**](https://shizuku.rikka.app/) runs a helper with `adb shell`
  rights, no root needed. Start it once after each reboot with wireless
  debugging (Android 11+) or `adb`.
- **Root** (`su`, from Magisk, KernelSU or similar).

Settings, *Access level* chooses: *Automatic* (Shizuku when it is running and
granted, otherwise normal; it never triggers a root prompt by itself),
*Normal app only*, *Shizuku* or *Root*. The chip in the app bar shows the
level in use, and *Check again* re-detects it.

## What each level shows

| Data | Normal app | Shizuku or root |
|---|---|---|
| CPU | Clock speed as a share of maximum | Real utilisation from `/proc/stat`, per core |
| Process list | Hidden by Android | All processes, with CPU %, memory and state |
| Per-app battery use | No | From `dumpsys batterystats` |
| GPU busy | Some devices | Most devices |
| Thermal zones | Thermal status and battery; zones on some devices | All zones |
| Disk I/O | TurboMon's own | All disks, from `/proc/diskstats` |
| RAM, battery, network, storage, Wi-Fi, Bluetooth | Yes | Yes |

"Some devices" depends on the vendor's SELinux policy. TurboMon tries the
normal route first and says when a value is hidden.

## How it works

Privileged reads are plain read-only shell commands (`cat /proc/stat`,
`top`, `cat /sys/class/thermal/...`, `dumpsys batterystats`). Each refresh
is batched into one script, so Shizuku or `su` is called once per refresh,
not once per file. Nothing is written with elevated rights.

Shizuku runs the script through a small user service (`ShellService`) bound
over Shizuku's API; TurboMon asks for Shizuku's permission the first time you
choose it. With root, your root manager asks once. If Shizuku stops, for
example after a reboot, TurboMon falls back to normal mode.

## Starting Shizuku with adb

```fish
adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh
```
