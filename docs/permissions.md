# Permissions

TurboMon has **no internet permission**: nothing it measures can leave the
phone unless you share a snapshot yourself. Runtime permissions are asked for
the first time you use the feature that needs them, never at install.

| Permission | Feature | Notes |
|---|---|---|
| Nearby Wi-Fi devices (Android 13+) | Wi-Fi tab | Declared `neverForLocation`. |
| Location (Android 12 and older) | Wi-Fi tab | Older Android only returns scan results to apps with location. TurboMon never reads your location. |
| Wi-Fi state, change Wi-Fi state, network state | Wi-Fi tab, network speed | Reading scan results, starting scans, following the connected network. |
| Nearby devices: Bluetooth scan and connect (Android 12+) | Bluetooth tab | Scan is declared `neverForLocation`; connect is needed for names and the paired list. Android 11 and older use the legacy Bluetooth permissions. |
| Usage access | Per-app data use and storage | Granted in Android's Settings; TurboMon opens the page. |
| Query all packages | App names | Turns UIDs into app names in the per-app lists. |
| Notifications (Android 13+) | Background scanning, alerts | The background service must show a notification. |
| Foreground service (special use) | Background scanning | Only while a run is active. |
| Display over other apps | Floating overlay | Only if you turn the overlay on. |

## Without a permission

Every tab works with what it has. If you deny Wi-Fi or Bluetooth permission
the tab says what is missing and offers *Try again*. Without usage access
the per-app lists explain how to grant it.

## Privacy in snapshots

Snapshots leave out Wi-Fi BSSIDs and Bluetooth addresses unless you tick
them in the snapshot sheet, because router addresses can be looked up to
find where you are. SSIDs and device names stay in; edit the file before
sharing if that matters.
