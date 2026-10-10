# Features

TurboMon has five tabs, a snapshot button and a settings screen. Live
screens sample every 2 seconds by default (Settings, *Refresh rate*: 1, 2 or
5 s) and graphs keep the last 4 minutes (*Graph window*: 1, 4 or 15 min).
Sampling stops when the app leaves the screen unless
[background scanning](./background-scanning.md) is on.

Bars and graph lines are coloured by load: green below 50 %, amber below
80 %, red above.

## System

The `top`-style view.

- **CPU**: total and one bar per core. A normal app cannot read
  `/proc/stat`, so TurboMon shows each core's clock as a share of its
  maximum instead and says so (*CPU clock*). With
  [Shizuku or root](./shizuku-and-root.md) it shows real utilisation. If the
  device hides clock speeds too, the card says what would unlock them.
- **Memory and GPU**: RAM used and available, cached, swap (zram), and GPU
  busy % and clock where the vendor exposes them (Adreno, Mali). The GPU bar
  is hidden rather than guessed when the device does not expose it.
- **Live graphs**: CPU, RAM and GPU. Tap the CPU graph to split it into one
  small graph per core.
- **Processes**: PID, name, CPU %, resident memory and state, sorted by CPU,
  plus each app's estimated battery use (mAh, from `dumpsys batterystats`).
  Android hides other apps' processes from normal apps, so this needs
  Shizuku or root; without them the card says so.

## Power

- **Battery**: level, charging state and source, current in mA (sign and
  units normalised across vendors), power in watts, voltage, temperature and
  health, with graphs for level, power and temperature.
- **Temperatures**: Android's thermal status and headroom, battery
  temperature, and every readable thermal zone (all zones with Shizuku or
  root).

## I/O

- **Network speed**: download and upload, split into Wi-Fi and mobile, with
  a live graph. *Per app* lists data use by app over the last 24 hours (needs
  *Usage access*).
- **Storage**: each volume's used and free space. *Per app* lists the
  largest apps by app, data and cache size (needs *Usage access*).
- **Disk I/O**: read and write throughput and operations per second for all
  disks from `/proc/diskstats` (Shizuku or root), or TurboMon's own I/O
  otherwise.

## Wi-Fi

Three views, switched at the top:

- **Networks**: the connected network (signal, link speed, frequency,
  channel, standard) and every network in range with signal, band, channel,
  width and security.
- **Channels**: per band (2.4, 5, 6 GHz) an animated channel graph with each
  network drawn as a curve across the channels it occupies; bars with the
  strongest signal and network count per channel; a suggested least-crowded
  channel (1, 6 or 11 on 2.4 GHz, non-DFS on 5 GHz, PSC on 6 GHz); and a waterfall of
  channel use over the last scans.
- **Signal**: signal over time for pinned networks (pin from the list).

Android throttles apps to 4 scans per 2 minutes. TurboMon asks for a scan
every 5 seconds, falls back to every 30 seconds while Android refuses, and
also uses scans other apps trigger. The connected link is polled every
second, so its signal stays live between scans. If *Wi-Fi scan throttling*
is off in Developer options, scans really arrive every 5 seconds. Scanning
runs only while the tab is open (or in the background if you chose it).

## Bluetooth

- **Nearby**: Bluetooth LE devices from a live scan, with name, signal, type
  and maker (from the advertised company ID); *Classic* runs a 12-second
  classic discovery. Devices not seen for a minute drop off.
- **Signal**: signal over time for pinned devices, about one point per
  second.
- **Paired**: paired devices and whether each is connected, with battery
  level where the device reports it.

## Snapshots

The camera button builds a snapshot of what TurboMon has measured: a
Markdown file with an instruction line for an LLM, the device context,
rule-based findings (for example *`com.example` averaged 34 % CPU over 12
samples*, or *battery draining 720 mA with screen off*) and one JSON block
with all the data. See [snapshot-schema.md](./snapshot-schema.md).

The sheet can *Share* it (any app: a chat, an LLM app, email), *Save* it
inside TurboMon, *Preview* it, or open the *Saved* list. Wi-Fi BSSIDs and
Bluetooth addresses are left out unless you tick them, and you can choose
whether background history goes in.

## Alerts

Settings, *Threshold alerts*: CPU load, temperature, battery drain and RAM,
each with a threshold, how long it must be held, and whether to save a
snapshot when it fires. All are off by default. An alert fires once per
excursion and re-arms when the value drops back. Alerts are checked by the
background service, so they work with the app closed.

## Widget, overlay and quick-settings tile

- A home-screen **widget** shows CPU, RAM, battery and temperature. It
  updates on every background sample while scanning runs, and every 30
  minutes otherwise.
- A floating **overlay** (Settings, Background scanning, *Floating overlay*)
  shows the same numbers over other apps while scanning runs; tap it to open
  TurboMon. It needs *Display over other apps*.
- A **quick-settings tile** starts and stops background scanning with your
  last plan.
