# Snapshot format

A snapshot is one Markdown file named `turbomon-YYYYMMDD-HHMMSS.md`. It is
written so you can paste or share it into any LLM chat and ask "what is
draining my phone?" with no other context. Code that builds it:
`lib/services/snapshot.dart`.

## Layout

1. `# TurboMon snapshot <time>`
2. A quoted instruction for the LLM: what the file is, what to look for, and
   which schema the JSON follows.
3. `## Context`: reason (manual, alert, end of background run), device,
   Android version and kernel, access level, time window, app version, and a
   warning when CPU values are only a frequency proxy.
4. `## Findings`: rule-based observations, each tagged *High*, *Medium* or
   *Low*, for example a process averaging high CPU, sustained battery drain,
   thermal throttling, low memory or storage, alerts that fired.
5. `## Top processes`: a table of the busiest processes (only with Shizuku
   or root).
6. `## Data`: one fenced `json` block with everything, described below.

## JSON, schema `turbomon.snapshot/1`

| Key | Content |
|---|---|
| `schema` | Always `turbomon.snapshot/1`. A breaking change bumps the number. |
| `takenAt`, `window.start`, `window.end` | ISO 8601 UTC. |
| `reason` | Why the snapshot was taken. |
| `app`, `device`, `access` | App version; manufacturer, model, Android release, SDK, kernel; the access level label (normal app, Shizuku or root). |
| `cpuIsFrequencyProxy` | `true` when `series.cpu` is core frequency, not utilisation. |
| `series` | Every graph series: `start` (ISO time), `times` (Unix seconds) and `values`, oldest first, `null` where not measured. |
| `memory` | `totalKb`, `availableKb`, `cachedKb`, `swapTotalKb`, `swapFreeKb`. |
| `battery` | `levelPercent`, `status`, `plugged`, `health`, `tempC`, `voltageMv`, `currentMa` (positive while charging, negative while draining), `powerW`. |
| `thermal` | Android thermal `status` (0 to 6) and `statusName`, `headroom`, `zones` (`type`, `celsius`). |
| `storage` | Volumes with total and free bytes. |
| `diskIo` | Per disk: `readBps`, `writeBps`, `readOps`, `writeOps`. |
| `processes` | Up to 20: `pid`, `user`, `name`, `cpu` %, `rssKb`, `state`, and where known `batteryMah`, `ioReadBps`, `ioWriteBps`. |
| `wifi` | `connected` (SSID, signal, link speed, ...) and `networks` (`ssid`, `bssid`, `rssi`, `frequency`, `channel`, `widthMhz`, `security`, `standard`). |
| `bluetooth` | `connected` and `nearby` devices (`name`, `address`, `rssi`, `type`, `maker`). |
| `alerts` | Alerts in the window: `kind`, `value`, `limit`, `since`, `at`. |
| `history` | Background samples in the window, as written to the history files. |
| `raw` | Raw privileged shell output behind the process list, when any. |

`bssid` and `address` are the string `redacted` unless *Include Wi-Fi and
Bluetooth addresses* is on.
