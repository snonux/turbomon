# Device test checklist

Unit and widget tests (`flutter test`) cover the parsers, channel maths,
settings, alerts, the snapshot builder and every screen against a fake
platform. What they cannot cover is real hardware, permissions and Android's
background rules, so before a release install the release APK on a phone
(and ideally an emulator) and go through this list. Record the Android
version, the device, and whether Shizuku or root was active.

## Normal app (no Shizuku, no root)

- [ ] First start asks for no permission. Top shows CPU (marked *CPU freq*),
      per-core bars, RAM and a hint that the process list needs Shizuku or root.
- [ ] Graphs: CPU, RAM, battery, network and temperature lines move; colours
      change with load (run something heavy, the CPU line turns amber or red).
- [ ] Settings, refresh rate 1/2/5 s and graph window 1/4/15 min take effect.
- [ ] Device: battery current has the right sign (negative unplugged, positive
      charging), power in W, temperature; thermal status; storage volumes.
- [ ] Usage access: granting it shows largest apps and per-app data use.
- [ ] Wi-Fi tab asks for Nearby devices (13+) or Location (12-), then lists
      networks; the connected one shows link speed; channel graph, bars,
      waterfall and signal graph fill in; 2.4/5/6 GHz switch works.
- [ ] Leaving the Wi-Fi tab stops scanning (no new scans in the waterfall).
- [ ] Bluetooth tab asks for Nearby devices, then lists devices with maker;
      a phone or earbuds rotating addresses show as one row; connected
      devices list; signal graph follows ticked devices.
- [ ] Snapshot button saves a file; Snapshots lists it; share opens the share
      sheet with the Markdown attached; *Save as* writes to a chosen folder;
      delete removes it. BSSIDs and Bluetooth addresses read `redacted`.
- [ ] Paste a snapshot into an LLM: it reads the findings and the JSON.

## Background scanning

- [ ] Off by default; no notification.
- [ ] Turning it on asks for notifications (13+) and shows the service
      notification with live values and a working **Stop**.
- [ ] Each monitor can be ticked off; intervals apply.
- [ ] Auto-stop after 15 min stops the service and leaves a snapshot.
- [ ] Auto-stop at a time of day and below a battery level both stop it.
- [ ] Presets fill the plan; *Save current choice as a preset* adds one.
- [ ] Graphs, History shows the samples after the app was closed.
- [ ] Alerts: lower the CPU limit to 10 % and the duration to 30 s, load the
      CPU, and get a notification plus an automatic snapshot; no second alert
      within 10 minutes.
- [ ] Quick-settings tile starts and stops scanning and shows its state.
- [ ] Widget: add it, it shows values; live while scanning runs.
- [ ] Overlay: asks for *Display over other apps*, floats over other apps
      while scanning runs, disappears on stop.
- [ ] Reboot or force-stop: the service does not restart on its own.

## With Shizuku or root

- [ ] Settings, *Elevated access* on *Automatic* picks Shizuku (or root);
      Top shows the level.
- [ ] CPU shows real usage (no *CPU freq* label); process list shows all
      processes with CPU % and memory.
- [ ] GPU busy, all thermal zones and disk I/O appear where the device has them.
- [ ] A snapshot's process table includes battery mAh from batterystats.
- [ ] Stopping Shizuku falls back to normal mode without a crash.

## Release build

- [ ] `flutter build apk --release --split-per-abi` succeeds and the arm64
      APK installs over the previous version.
- [ ] Icon: launcher, adaptive shapes, themed (monochrome) icon on Android 13+.
