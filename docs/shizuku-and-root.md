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
| Process list | Hidden by Android | Processes across apps and the system, with CPU %, memory and state |
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

On an unrooted phone, ADB starts Shizuku as Android's `shell` user (UID
2000). TurboMon keeps its ordinary app identity and talks to its privileged
helper through Android's Binder IPC. The helper reads the system data and
returns it to TurboMon to parse and display. Shell access remains subject
to Android's restrictions; it does not grant root (UID 0). See
[Shizuku's explanation](https://shizuku.rikka.app/introduction/).

## Set up Shizuku to see other processes

This USB setup was confirmed on a Pixel 7 Pro running GrapheneOS, Android
17, with Shizuku 13.6 and TurboMon 0.1.0. TurboMon displayed real CPU
utilisation and a process table containing `system_server`,
`surfaceflinger` and other processes. Root was not needed.

### 1. Install Shizuku

Install it from one of the sources on the
[official download page](https://shizuku.rikka.app/download/), such as its
GitHub release. Open Shizuku on the phone after installation.

### 2. Start its service using a computer

1. Install [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools)
   on the computer so the `adb` command is available.
2. On the phone, enable *Developer options* (tap *Build number* seven times
   under *About phone*), then enable *USB debugging* in Developer options.
3. Connect the phone by USB, unlock it, and approve the debugging request
   for your computer. Run `adb devices` on the computer: the phone should
   be listed as `device`. If it says `unauthorized`, check the phone for the
   approval dialog.
4. In Shizuku, find *Start by connecting to a computer* and tap *View
   command*. Copy that command and run it in a terminal on the computer.
5. Check that Shizuku reports that it is running.

Use the command shown by your installed Shizuku version. Shizuku 13.6
starts an executable named `libshizuku.so` in its installed app directory;
that directory can change after an update. Older instructions use
`adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh`,
which can fail with *No such file or directory* on newer releases.

The USB method above was tested on the phone. For starting without a
computer on Android 11+, see Shizuku's
[wireless debugging guide](https://shizuku.rikka.app/guide/setup/#start-via-wireless-debugging).

### 3. Authorise TurboMon

1. Open TurboMon, then *Settings → Access level → Shizuku*.
2. Approve TurboMon's Shizuku request. In the tested version, choose
   *Allow all the time*. This authorises TurboMon to use the running
   service; it does not keep the service running through a reboot.
3. Return to *System*. The access chip should say `shizuku`, the live CPU
   graph should say *CPU* instead of *CPU clock*, and *Processes* should
   show *via Shizuku (ADB shell)* with names, CPU % and memory usage.

If the chip stays `normal`, check that Shizuku is running and TurboMon is
allowed in Shizuku's authorised apps, then tap *Check again* in TurboMon's
access settings. *Automatic* can also use Shizuku once it is running and
TurboMon is authorised.

### GrapheneOS

The tested phone worked with its existing GrapheneOS security settings,
including successfully starting TurboMon's shell helper. No exploit
protection settings were changed. Other OS or Shizuku versions may differ;
check the [official setup notes](https://shizuku.rikka.app/guide/setup/)
and [GrapheneOS documentation](https://grapheneos.org/usage) if starting the
service or connecting an authorised app fails.

### After a reboot

Start Shizuku again with the command currently shown by its app, or use its
wireless debugging method. Recheck TurboMon's access level afterwards.
Until the service is available, TurboMon continues with its normal-app
readings. You can revoke TurboMon's approval from Shizuku's authorised-app
list whenever you want to stop sharing shell access.

## Checking what is available

A USB debugging connection gives `adb shell` its own shell rights; it does
not give those rights to TurboMon. A working `adb shell top` therefore does
not mean the app can show the same processes. TurboMon needs a running,
authorised Shizuku service or a root manager that grants its `su` request.
Android's ordinary app permissions do not unlock the process list.

These checks only read device state:

```fish
adb shell id
adb shell 'command -v su'
adb shell pm path moe.shizuku.privileged.api
adb shell pidof shizuku_server
```

An empty `su` lookup means no `su` is exposed to the ADB shell; a root
manager may expose it differently to apps. Selecting *Root* in TurboMon
checks `su -c 'id -u'` from the app and may show the root manager's approval
dialog. If that check fails, TurboMon uses normal mode and explains that
`su` is missing or did not grant root. With Shizuku absent or stopped, choose
normal mode or set up Shizuku before expecting privileged readings.
