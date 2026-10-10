Captured command output for the parser tests.

- `meminfo.txt`, `stat_before.txt`, `stat_after.txt`, `loadavg.txt`,
  `top_quiet.txt`, `top_header.txt`: an Android 14 x86_64 emulator, read
  with `adb shell` (shell rights, as Shizuku has).
- `batterystats_uids.txt`: the `UID x: mAh` lines of `dumpsys batterystats`
  in Android 13's format; the emulator reports no per-UID power, so these
  lines follow the platform's `BatteryUsageStats.dump` layout by hand.
- `diskstats.txt`: `/proc/diskstats` in the kernel's documented layout; the
  emulator's shell user may not read it.
