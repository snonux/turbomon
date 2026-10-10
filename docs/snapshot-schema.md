# Snapshot format

A snapshot is one Markdown file named `turbomon-YYYYMMDD-HHMMSS.md`, written
so you can paste or share it into any LLM chat and ask "what is draining my
phone?" with no other context. The code is `lib/services/snapshot.dart`; the
golden test `test/fixtures/snapshot_golden.md` is a complete example.

## Layout

1. `# TurboMon snapshot`
2. A quoted instruction for the LLM: what the file is, what to look for, and
   which schema the JSON follows.
3. `## Context`: device, Android version and kernel, access level, snapshot
   time and window, and whether CPU figures are utilisation or only clock
   speed.
4. `## Findings`: rule-based observations, for example a process averaging
   high CPU, sustained battery drain, heat or throttling, low RAM, a nearly
   full volume, a weak or crowded Wi-Fi channel, and alerts that fired.
5. `## Data`: one fenced `json` block, described below.

## JSON, schema `turbomon.snapshot/1`

Times are ISO 8601 in the phone's local time. Any breaking change bumps the
schema number, this page and the golden test together.

| Key | Content |
|---|---|
| `schema` | Always `turbomon.snapshot/1`. |
| `generatedAt`, `window.start`, `window.end` | When the snapshot was taken and the span its data covers. |
| `device` | `manufacturer`, `model`, `release`, `sdk`, `kernel`. |
| `access` | Access level: normal app, Shizuku or root. |
| `cpuIsFrequencyProxy` | `true` when CPU values are clock speed as a share of maximum, not utilisation. |
| `current` | The latest reading of `cpu`, `memory`, `gpu`, `battery`, `network`, `thermal` and `diskIo`; `null` where not measured. |
| `series` | Graph series by name (`cpu`, `ram`, `gpu`, `batteryPower`, `batteryPercent`, `temperature`, `netRx`, `netTx`, `diskRead`, `diskWrite`), each with `unit` and `points` as `[unixMillis, value]` pairs, oldest first. |
| `cores` | Per-core CPU series, same point format. |
| `processes.top` | Up to 20 processes: `pid`, `user`, `name`, `cpuPercent`, `rssBytes`, `state` and, where known, `batteryMah`. Only with Shizuku or root. |
| `processes.averages` | Up to 20 processes by average CPU over the window: `name`, `avgCpu`, `peakCpu`, `samples`. |
| `storage` | Volumes: `label`, `totalBytes`, `freeBytes`, `removable`. |
| `wifi` | `link` (connected network) and `networks` (SSID, signal, frequency, channel, width, security, standard). |
| `bluetooth` | `nearby` and `paired` devices (name, signal, type, maker, connected). |
| `alerts` | Alerts that fired: `metric`, `threshold`, `durationSeconds`, `value`, `time` and `culprit` (top process) when known. |
| `history` | Background samples, as written to the history files, when included. |
| `findings` | The findings above, as strings. |
| `diagnostics` | Raw `dumpsys` output by service, only with Shizuku or root. |

Wi-Fi `bssid` and Bluetooth `address` fields appear only when ticked in the
snapshot sheet.
