# Handoff: test TurboMon on a real phone

You are taking over testing of **TurboMon**, an Android system monitor
(Flutter app, package `org.buetow.turbomon`) in
[snonux/turbomon](https://github.com/snonux/turbomon). The code is merged to
`main`. It was tested on an Android 14 emulator with Shizuku; this round is
about what an emulator cannot show. Your job: install it on Paul's phone, work
through the checklist below, fix what breaks, and report back.

## State on 2026-10-10

- `main` (commit `50daac6`) holds the app, docs in `docs/`, screenshots in
  `docs/screenshots/` and F-Droid metadata in `fastlane/`.
- snonux/fdroid lists TurboMon in `apps.yml` (merged). It shows up in the
  F-Droid repo once a GitHub release with APKs exists.
- **No release yet.** The release workflow is staged at
  `ci/workflows/release.yml` because agents cannot write `.github/workflows/`.
  Paul has to move it before a release can run (see "Releasing" below).
- Read first: `AGENTS.md`, `docs/testing.md` (the full manual checklist and
  what the emulator run covered), `docs/building.md`.

## Rules

- Do not write under `.github/workflows/` and do not push tags; Paul does
  those, or a workflow run with a `tag` input does.
- Never create, print or commit a signing key or its passwords. The release
  key lives in Paul's foostore (`keys/f-droid/turbomon-release.jks.txt`,
  alias `turbomon`) and in the repo's `ANDROID_*` secrets. You do not need it
  for testing.
- The app must keep **no INTERNET permission**, and no Google Play Services,
  Firebase or analytics.
- Give Paul any commands in **fish** syntax.
- Fixes go on a branch with a PR into `main`, and must keep `flutter analyze`
  clean and `flutter test` green (75 tests as of now). Follow the existing
  style: Kotlin only in `packages/turbomon_platform`, sampling logic in Dart.

## 1. Get an APK onto the phone

Toolchain as in Quicklog: Flutter 3.47.5, AGP 8.11.1, Gradle 8.14,
Kotlin 2.2.20, JDK 17.

```fish
git clone https://github.com/snonux/turbomon; cd turbomon
flutter pub get
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Without `android/key.properties` this release build is signed with the
**debug key**. That is fine for testing, but the later F-Droid build is
signed differently, so uninstall this test build before installing from
F-Droid (`adb uninstall org.buetow.turbomon`).

If Paul has already moved the workflow and a v0.1.0 release exists, install
`app-arm64-v8a-release.apk` from that release instead; then F-Droid updates
it in place.

## 2. Note the phone

Record model, Android version, SoC (Qualcomm, Exynos, Tensor, MediaTek) and
whether Shizuku and/or root is available. These decide which sysfs paths
exist (GPU: `kgsl` on Qualcomm, `mali` elsewhere; thermal zone names; CPU
frequency files), so many real-phone bugs are SoC-specific.

## 3. Test what the emulator could not

Work through the full list in `docs/testing.md`, but spend most time here:

**Bluetooth (untested so far: the emulator's stack crashed)**
- [ ] Asks for Nearby devices, then lists BLE devices with maker and RSSI.
- [ ] Rotating random addresses group into one device, not dozens.
- [ ] *Classic* discovery finds a non-BLE device; *Paired* lists bonded
      devices with names; connected ones are marked.
- [ ] Signal view: pinned devices draw a line over time.
- [ ] Turning Bluetooth off and on while on the tab recovers.

**Battery (the emulator battery never discharges)**
- [ ] Unplugged: current is negative, watts and drain look plausible against
      Android's own battery screen.
- [ ] Charging: sign flips; charging power graph moves.
- [ ] Some phones report current in mA, others in µA; check the number is not
      off by 1000.
- [ ] A *Battery drain* alert with a low threshold fires.
- [ ] Auto-stop *Below a battery level* stops a background run.

**Background scanning over real time**
- [ ] *Overnight drain check* runs for hours with the screen off; history
      keeps growing (Doze, battery optimisation, OEM task killers).
- [ ] Auto-stop *At a time of day* fires.
- [ ] Notification **Stop**, the quick-settings tile and the app switch each
      stop the run and save the end-of-run snapshot.
- [ ] Widget and overlay keep updating while the screen is on.
- [ ] Battery cost of a run is reasonable (TurboMon in the per-process list
      and in Android's battery screen).

**Wi-Fi with real networks**
- [ ] Asks for location (and Nearby Wi-Fi devices on 13+), then lists
      networks.
- [ ] With location services switched off, scans return nothing; the app has
      no explicit hint for that yet, so note what the user sees.
- [ ] Several networks on 2.4, 5 and (if supported) 6 GHz; channel graph,
      bars, waterfall, *least crowded* suggestion look right.
- [ ] Connected-network card: SSID, RSSI, link speed, channel; RSSI moves as
      you walk away from the router.

**Shizuku and root on real hardware**
- [ ] *Automatic* picks Shizuku; real CPU %, process list (TurboMon's own
      `top` and `@@TM@@` probes must not appear), per-app mAh, all thermal
      zones, GPU busy %, disk I/O.
- [ ] Stopping Shizuku falls back to normal mode without a crash, and coming
      back recovers.
- [ ] With root, the *Root* level gives the same data.
- [ ] Without either: CPU shows clock speed as a share of max (or a hint
      when the phone hides clocks), no process list, no crash.

**Look and feel**
- [ ] Light and dark theme; themed (monochrome) icon on Android 13+.
- [ ] Long text does not overflow on a narrow phone or with a large font size.

## 4. Collect evidence

- Logs: `adb logcat --pid=(adb shell pidof org.buetow.turbomon)` (fish), plus
  `adb logcat -b crash` for crashes.
- Take a TurboMon snapshot (camera icon, *Save*) whenever something looks
  wrong; it carries device info, readings and Shizuku diagnostics. Keep
  BSSIDs and Bluetooth addresses off unless needed.
- Screenshots: `adb exec-out screencap -p > name.png`.

## 5. Report back

For each checklist item: pass, fail (with log or snapshot) or not testable on
this phone. Fix failures on a branch and open a PR into `main`; small fixes
can share one PR. Put the device model and results in the PR description and
add a "Last run" note for the phone to `docs/testing.md`.

## Releasing (after testing, or in parallel)

1. Paul moves the workflow on `main`:

   ```fish
   cd turbomon; git switch main; git pull
   mkdir -p .github/workflows
   git mv ci/workflows/release.yml .github/workflows/release.yml
   git commit -m "Enable the release workflow"; git push
   ```

2. Run it with tag `v0.1.0` (or the next version if fixes changed
   `pubspec.yaml`):
   `gh workflow run release.yml -R snonux/turbomon --ref main -f tag=v0.1.0`
3. When the release has its three `app-*-release.apk` assets, snonux/fdroid's
   scheduled `publish.yml` picks them up within six hours; run it by hand to
   publish at once (no `FDROID_DISPATCH_TOKEN` is set, so the release does
   not trigger it). TurboMon then appears in
   `https://snonux.github.io/fdroid/repo`.
4. Check the release APK's certificate matches SHA-256
   `97:9E:BE:3D:40:CB:2D:10:4C:27:F9:9A:99:6C:78:EC:BC:D1:16:1D:FE:00:2A:2C:13:4F:20:B0:57:3B:D3:92`
   (`apksigner verify --print-certs`). `docs/releasing.md` has the details.
