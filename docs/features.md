# Features

TurboMon has five tabs, a snapshot button and a settings screen. Values
refresh every 2 seconds by default (Settings, *Refresh rate*), and graphs show
the last 4 minutes (Settings, *Graph window*). Sampling pauses while the app is
in the background unless [background scanning](./background-scanning.md) is
on.

## Top

A `top`-like table of the phone right now.

- **CPU**: total usage and one bar per core with its current frequency. On a
  normal (unprivileged) install Android blocks `/proc/stat`, so TurboMon shows
  each core's frequency relative to its maximum instead, marked *CPU freq*.
  With [Shizuku or root](./shizuku-and-root.md) it shows real CPU time.
- **RAM**: used, available, cached and swap (zram).
- **GPU**: busy percentage, read from the vendor's sysfs node (Adreno, Mali,
  PowerVR). Most phones only expose it to Shizuku or root.
- **Processes**: the busiest processes with CPU %, memory and state. Android
  hides other apps' processes from normal apps since Android 7, so this list
  needs Shizuku or root; without them TurboMon shows its own process and says
  why.

Every bar is coloured by load: green below 50 %, amber below 80 %, red
above.

## Graphs

Live line graphs for CPU (total and per core), RAM, GPU, battery power and
drain, network download and upload, the hottest thermal zone and battery
temperature, and disk read and write rates. The line colour follows the
current value with the same load scale. Switch to **History** to see what the
background service recorded over the last days.

## Device

- **Battery**: level, charging state, current in mA (units and sign are
  normalised across vendors), power in watts, voltage, temperature, health,
  remaining charge and the average drain over the graph window. With Shizuku
  or root, snapshots also carry each app's estimated battery use since the
  last full charge, from `dumpsys batterystats`.
- **Temperatures**: Android's thermal status and headroom, plus every thermal
  zone the device exposes.
- **Storage**: each volume's size and free space, and, once *Usage access* is
  granted, the largest apps by app, data and cache size.
- **Disk I/O**: read and write throughput and operations per second per disk
  (needs Shizuku or root on most devices).
- **Network**: current download and upload speed, split into mobile data
  and Wi-Fi, and data use per app over the last 24 hours (needs *Usage
  access*).

## Wi-Fi

- Every network in range with SSID, signal strength, band, channel, channel
  width, security and Wi-Fi standard. The network you are connected to is
  pinned on top with its link speed.
- **Channel graph**: each network drawn as a curve over the channels it
  occupies, height by signal strength, for 2.4, 5 and 6 GHz.
- **Channel bars**: networks per channel and the strongest signal on each,
  plus a suggested least-crowded channel (1, 6 or 11 on 2.4 GHz).
- **Waterfall** of channel use over time, and a signal graph of the 5
  strongest networks or the ones you tick.

Android limits apps to 4 Wi-Fi scans every 2 minutes, so TurboMon scans every
30 seconds and also picks up results from scans other apps trigger. If
*Wi-Fi scan throttling* is turned off in Developer options, TurboMon notices
and scans every 5 seconds. Scanning only runs while the Wi-Fi tab is open
(or in the background if you chose it).

## Bluetooth

Nearby Bluetooth LE and classic devices with name, signal, type and maker
(from the advertised manufacturer ID). Devices that rotate their random
address are grouped, so one pair of earbuds is one row. Connected devices are
listed separately, with their battery level where the device reports it. A
signal graph follows the 5 strongest devices, or the ones you tick.

## Snapshots

The camera button saves a snapshot of everything on screen plus the recent
graph data: a Markdown file with an instruction for an LLM, the device
context, rule-based findings (for example *`com.example` averaged 34 % CPU*,
or *battery drained 720 mA with the screen off*), the top processes and one
JSON block with all the data. See [snapshot-schema.md](./snapshot-schema.md).

Snapshots are listed under *Snapshots*, where you can share one (to a chat
app, an LLM app, email), save it to a folder, or delete it. Wi-Fi BSSIDs and
Bluetooth addresses are replaced by `redacted` unless you turn on *Include Wi-Fi
and Bluetooth addresses* in Settings.

## Alerts

Notifications when CPU stays above 80 %, the hottest zone above 45 °C,
battery drain above 600 mA, or (off by default) RAM above 90 % for one
minute. Each alert can take a snapshot automatically and then stays quiet for
10 minutes. All limits are in Settings.

## Widget, overlay and quick-settings tile

- A home-screen **widget** shows CPU, RAM, battery, power and temperature.
  It updates live while background scanning runs, and every 30 minutes
  otherwise.
- A floating **overlay** shows the same numbers on top of other apps while
  background scanning runs (needs *Display over other apps*).
- A **quick-settings tile** starts and stops background scanning with your
  last plan.
