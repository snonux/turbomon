# Permissions

TurboMon has **no internet permission**: nothing it measures can leave the
phone unless you share a snapshot yourself. Each permission below is asked for
the first time you use the feature that needs it, never at install.

| Permission | Feature | Notes |
|---|---|---|
| Nearby Wi-Fi devices (Android 13+) | Wi-Fi tab | Declared `neverForLocation`. |
| Location (Android 12 and older) | Wi-Fi tab | Older Android only returns scan results to apps with location. TurboMon does not read your location. |
| Wi-Fi state, change Wi-Fi state | Wi-Fi tab | Reading and starting scans. |
| Nearby devices / Bluetooth scan and connect | Bluetooth tab | Scan is declared `neverForLocation`. Connect is needed to read names of paired and connected devices. |
| Usage access | Per-app storage sizes and data use | Granted in Android Settings; TurboMon opens the page for you. |
| Query all packages | Labelling apps | Turns UIDs and package names into app names in lists and snapshots. |
| Notifications | Alerts, background scanning | Android 13+ asks; the background service must show a notification. |
| Foreground service (special use) | Background scanning | Only while you have background scanning on. |
| Display over other apps | Floating overlay | Only if you turn the overlay on. |

## Without a permission

Every tab works with what it has. If you deny Wi-Fi or Bluetooth
permissions, those tabs say what is missing and offer to ask again. Without
usage access, storage shows volumes but not apps.

## Privacy in snapshots

Snapshots replace Wi-Fi BSSIDs and Bluetooth addresses with `redacted`,
because router addresses can be looked up to find where you are. Turn on
*Include Wi-Fi and Bluetooth addresses* in Settings if you need them. SSIDs
and device names stay in; edit the file before sharing if that matters.
