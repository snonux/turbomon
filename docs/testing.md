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
