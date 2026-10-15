# Testing

`flutter test` covers the parsers (against real captures in
`test/fixtures/`), privilege detection, settings, alerts, channel analysis,
the snapshot builder (golden file), history, the background runner and the
Wi-Fi and Bluetooth controllers against a fake platform. Regenerate the
snapshot golden with `UPDATE_GOLDEN=1 flutter test test/snapshot_test.dart`
after an intended change.

What unit tests cannot cover is real hardware, permissions and Android's
background rules. Before a release, install the release APK on a phone and
go through this list.

## Normal app

- [ ] First start asks for nothing. System shows *CPU clock* (or a hint when
      clocks are hidden), RAM, live graphs, and the process-list hint.
- [ ] Settings: refresh rate and graph window take effect.
- [ ] Power: current sign is negative unplugged and positive charging;
      watts, temperature, thermal status.
- [ ] I/O: network speed moves during a download; storage volumes; *Per app*
      asks for usage access, then lists apps.
- [ ] Wi-Fi asks for location (and Nearby Wi-Fi devices on 13+), then lists
      networks; channel graph, bars, waterfall and pinned-signal graph fill in
      for each band.
- [ ] Bluetooth asks for its permission, then lists nearby devices with
      maker; *Classic* discovery; paired list.
- [ ] Snapshot: share, save, preview, saved list; BSSIDs and addresses only
      when ticked. Paste one into an LLM.

## Background

- [ ] Off by default. Starting it asks for notifications (13+) and shows the
      notification with values and **Stop**.
- [ ] Presets and *Save current*; auto-stop after a time, at a time of day,
      and below a battery level; a snapshot is saved on stop.
- [ ] An alert with a low threshold fires once and saves a snapshot.
- [ ] Quick-settings tile starts and stops the last plan.
- [ ] Widget shows values and updates while scanning runs.
- [ ] Overlay asks for *Display over other apps*, floats while scanning,
      opens the app on tap and disappears on stop.

## Shizuku or root

- [ ] *Automatic* picks Shizuku when it runs; the chip shows the level.
- [ ] Real CPU %, the full process list with mAh, all thermal zones and
      disk I/O.
- [ ] Stopping Shizuku falls back to normal mode without a crash.

## Release build

- [ ] `flutter build apk --release --split-per-abi` succeeds and installs
      over the previous version.
- [ ] `aapt dump permissions` shows no `INTERNET`.
- [ ] Launcher, adaptive and themed (monochrome) icons look right.

## Last run: v0.1.0 on an emulator

Android 14 (API 34) x86_64 emulator with Shizuku, release build. Everything
above passed except what the emulator cannot do, which unit tests cover
instead: its Bluetooth stack crashes, so only the *Bluetooth is off* state
was checked; its battery is a fixed fake that never discharges, so drain
alerts and the battery-level auto-stop did not run; and it has one access
point. Auto-stop at a time of day was not waited for. Check these on a phone.
[phone-testing-handoff.md](./phone-testing-handoff.md) is the brief for that.

## Phone access investigation: 2026-10-15

Pixel 7 Pro, Tensor GS201, GrapheneOS / Android 17 (API 37), `user` build; installed
TurboMon v0.1.0, build 12 (target API 36). This was a read-only ADB
investigation of access availability, with no APK replacement or device
settings changes.

- **Confirmed:** ADB runs as UID 2000 (`shell`), not UID 0. `command -v su`
  found nothing, the usual `su` paths were absent, and `su -c 'id -u'`
  returned exit 127 (`inaccessible or not found`). No usable root access was
  exposed to the ADB shell; root access from TurboMon was not exercised.
- **Confirmed:** Shizuku's package (`moe.shizuku.privileged.api`) was not
  installed and no `shizuku_server` process was running.
- **Confirmed:** The ADB shell could see 722 processes and read `/proc/stat`,
  `/proc/diskstats` and CPU 0's current clock. TurboMon's `top` command ran
  successfully from that shell. These are shell capabilities, not proof of
  app access; see [Shizuku and root](./shizuku-and-root.md).
- **Not testable in this session:** TurboMon's live process list, real CPU
  utilisation and other privileged readings, plus root/Shizuku grant and
  recovery flows. Install/start Shizuku and authorise TurboMon, or grant it
  root through an existing root manager, before checking those items. No
  privileged service was installed or enabled during this investigation.

Source review confirmed that *Automatic* selects normal mode when Shizuku
is unavailable, without probing root. Explicit *Root* checks for UID 0 and
falls back with an explanation if the check fails. This source review does
not replace checking those screens on the phone.

### Follow-up: Shizuku installed and authorised

Later in the same session, with the user's approval, installed the official
Shizuku 13.6.0.r1086.2650830c release and started its native
`libshizuku.so` executable through ADB. The server ran as UID 2000
(`shell`). No GrapheneOS exploit protection settings were changed.

The user selected Shizuku in TurboMon and approved *Allow all the time*.
The installed F-Droid build then showed the `shizuku` access chip, a live
*CPU* utilisation graph, and *Processes · via Shizuku (ADB shell)* with
other processes including `system_server` and `surfaceflinger`. This
confirms the app's privileged shell connection and process-list path on
this phone. The [setup tutorial](./shizuku-and-root.md#set-up-shizuku-to-see-other-processes)
records the successful steps.

Root, Shizuku restart after a phone reboot, service-stop recovery, wireless
debugging setup, and the remaining GPU/thermal/disk readings were not
verified by this follow-up. TurboMon's newly built APK was not installed.
