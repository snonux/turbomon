# Building

TurboMon uses the same toolchain as
[Quicklog](https://github.com/snonux/quicklog): Flutter from
`.flutter-version`, JDK 17 or 21 (Gradle 8.14 rejects 25+), AGP 8.11 and
Kotlin 2.2. It is Android only.

```fish
flutter pub get
flutter analyze
flutter test
flutter run                                   # debug build on a phone or emulator
flutter build apk --release --split-per-abi   # what a release ships
```

`flutter analyze` and `flutter test` must be clean before a change is done.
Anything touching Kotlin or `android/` also needs a release build, because
R8 and signing problems only show there.

## Layout

- `lib/services/`: the sampling and analysis logic in plain Dart. Parsers
  for `/proc`, sysfs and `dumpsys` (`proc_parsers.dart`), the system reader
  that picks the normal or privileged route (`system_reader.dart`,
  `access.dart`), the live `MonitorHub`, Wi-Fi and Bluetooth controllers,
  channel analysis, alerts, history and the snapshot builder.
- `lib/background/`: `BackgroundRunner`, run by the background service in
  a headless Flutter engine (`backgroundMain` in `lib/main.dart`).
- `lib/models/`, `lib/screens/`, `lib/widgets/`: data types, UI and the graph
  painters.
- `packages/turbomon_platform/`: a local Flutter plugin with all Kotlin
  code. `TurboMonPlatformPlugin` handles the method channel
  `org.buetow.turbomon/platform` and the event channels for Wi-Fi and
  Bluetooth; beside it are the foreground `MonitorService`, the widget, the
  quick-settings tile, the overlay, notifications, Shizuku's `ShellService`
  and the snapshot `FileProvider`. `lib/turbomon_platform.dart` is its typed
  Dart API.
- `test/`: unit tests against a fake platform (`test/support/`) and real
  captures from devices (`test/fixtures/`).

## Icon

`assets-src/make_icon.py` writes the SVGs and `assets-src/render.js` renders
them with Playwright's Chromium. Then
`dart run flutter_launcher_icons` regenerates the launcher icons from
`logo.png`, `icon-foreground.png` and `icon-monochrome.png`. Copy a 512 px
render to `fastlane/metadata/android/en-US/images/icon.png`.

## Signing

`android/key.properties` is git-ignored and optional, as in Quicklog: with
it, all four of `storeFile`, `storePassword`, `keyAlias` and `keyPassword`
are required; without it release builds use the debug key and say so.
