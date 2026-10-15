# Permissions

TurboMon has **no internet permission**: nothing it measures can leave the
phone unless you share a snapshot yourself. Runtime permissions are asked for
the first time you use the feature that needs them, never at install.

| Permission | Feature | Notes |
|---|---|---|
| Location (precise) | Wi-Fi tab | Android only returns Wi-Fi scan results to apps with precise location, and location must be turned on. On Android 12+, approximate and precise access are requested together; choose precise for scans. TurboMon never reads your location. |
| Nearby Wi-Fi devices (Android 13+) | Wi-Fi tab | Asked together with location; declared `neverForLocation`. |
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

## If Android blocks a setting

Android can restrict sensitive settings for an installed app. If the usage
access page reports **Restricted setting**, open Android **Settings → Apps →
TurboMon**, then use **More → Allow restricted settings**, if offered. Return
to usage access and enable it. Only do this when you trust the installed app.
The available menu and wording depend on the Android version; see
[Android's restricted settings help](https://support.google.com/android/answer/12623953).

An F-Droid installation still uses Android's normal permission checks. An
update does not grant missing permissions automatically. If Wi-Fi or
Bluetooth stays blocked after *Try again*, check TurboMon's permissions in
Android Settings. Wi-Fi needs **Precise location** and location services on.
Android requires approximate and precise access in the same request on
Android 12+, including an upgrade from approximate; see the
[location permission guide](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime).

## Permission denied messages in ADB logs

In normal mode, Android blocks device-wide `/proc/stat`, GPU utilisation and
thermal sensor files on many phones. ADB logs can show SELinux `avc: denied`
messages for these reads while TurboMon falls back to the readings Android
allows. These file restrictions need optional Shizuku or root; granting
location, nearby devices or usage access does not unlock them. They are
separate from runtime permission failures and do not establish an installer
problem.

On a Pixel 7 Pro running Android 17 (API 37), the F-Droid-installed 0.1.0
(build 12) had location and nearby device grants and successfully displayed
Wi-Fi scans and the connected link. Usage access was off; its Settings
switch was available. Android also recorded an earlier restricted settings
rejection, which does not establish the cause of that earlier attempt or a
current restriction. No permissions were changed during this inspection.

## Privacy in snapshots

Snapshots leave out Wi-Fi BSSIDs and Bluetooth addresses unless you tick
them in the snapshot sheet, because router addresses can be looked up to
find where you are. SSIDs and device names stay in; edit the file before
sharing if that matters.
