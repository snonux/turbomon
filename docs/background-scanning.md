# Background scanning

Background scanning is **off by default**. When it is off, TurboMon only
samples while it is on screen, and the Wi-Fi and Bluetooth radios only scan
while their tab is open.

Turn it on in Settings, *Scan in the background*, or with the quick-settings
tile. A foreground service then runs with a notification that shows the
latest values and a **Stop** button.

## What to scan

Choose any of: CPU, RAM, GPU, battery, network, temperatures, disk usage,
disk I/O, Wi-Fi, Bluetooth and the process list. Each has its own interval:

| Monitor | Default interval |
|---|---|
| CPU, RAM, GPU, battery, network, temperatures, disk I/O | 30 s |
| Bluetooth, process list | 60 s |
| Wi-Fi | 120 s (Android allows 4 scans per 2 minutes) |
| Disk usage | 10 min |

The default plan is CPU, RAM, battery, network and temperatures. Radios cost
the most battery, so Wi-Fi and Bluetooth are off unless you choose them.

## When it stops

- **After a duration**: 15 min, 1 h (default), 4 h, 8 h or 24 h.
- **At a time of day**, e.g. 07:00 after an overnight check.
- **When the battery drops below** a level (20 % by default).
- **Never**: until you stop it.

When a run ends on its own TurboMon can take a snapshot of the whole run
(*Save a snapshot when a run stops*, on by default), and posts a notification.

## Presets

- *Overnight drain check*: CPU, battery, processes and temperatures for 8 h.
- *Quick 15-minute check*: CPU, RAM, battery, network and temperatures every
  5 to 10 s for 15 min.
- *Radio survey*: Wi-Fi, Bluetooth and battery for 1 h.

*Save current choice as a preset* adds your own.

## History

Samples are written to `files/history/YYYY-MM-DD.jsonl` in the app's private
storage, one JSON object per line, and kept for 7 days (Settings, *Keep
history for*). The Graphs tab's *History* view and snapshots read them.
Alerts are checked on every sample, so they also fire in the background.
