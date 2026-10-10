# Background scanning

Background scanning is **off by default**. Without it TurboMon samples only
while it is on screen, and the radios scan only while their tab is open.

Start it in Settings, *Background scanning*, or with the quick-settings tile.
A foreground service then runs with a notification showing the latest values
and a **Stop** button. The service runs TurboMon's own Dart sampling code in
a headless Flutter engine, so the background and the app measure the same
way.

## What to scan

Tick any monitor and set its interval:

| Monitor | Default interval |
|---|---|
| CPU, RAM, GPU, battery, network speed, disk I/O | 30 s |
| Temperatures, process list | 60 s |
| Wi-Fi, Bluetooth | 5 min |
| Disk usage | 15 min |

The default plan is CPU, RAM and battery. The process list needs Shizuku or
root. Android limits background Wi-Fi scans (as rarely as one every 30
minutes) and pauses unfiltered Bluetooth scans while the screen is off; the
screen warns about both.

## When it stops

- **After a set time**: 15 min, 1 h (default), 4 h, 8 h or 24 h.
- **At a time of day**, for example 07:00 after an overnight check.
- **Below a battery level** (20 % by default).
- **Never**: until you stop it.

With *Snapshot when it stops* on (the default) a run that ends saves a
snapshot of itself, listed under Snapshot, *Saved*.

## Presets

- *Overnight drain check*: CPU, battery and processes for 8 h.
- *Heat check*: CPU, GPU, temperatures and battery for 1 h.
- *Network watch*: network speed and Wi-Fi for 4 h.

*Save current* stores your own plan as a preset.

## History and alerts

Samples go to `history/YYYY-MM-DD.jsonl` in the app's private storage, one
JSON object per line, kept for 7 days (*Keep history for*: 1, 3, 7 or 14
days). Snapshots can include this history. [Alerts](./features.md#alerts)
are checked on every background sample.
