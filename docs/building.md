# Building

TurboMon uses the same toolchain as
[Quicklog](https://github.com/snonux/quicklog): Flutter from
`.flutter-version`, JDK 17 or 21 (Gradle 8.14 rejects 25+), AGP 8.11 and
Kotlin 2.2. It is Android only.

```fish
flutter config --jdk-dir=$HOME/jdk21
flutter pub get
flutter analyze
flutter test
flutter run                                   # debug build on a phone or emulator
flutter build apk --release --split-per-abi   # what a release ships
```

Before calling a change done, `flutter analyze` and `flutter test` must be
clean, and anything touching `android/` needs a release build too, because the
debug build hides signing and packaging problems.

## Layout

- `lib/parsers/`: pure functions for `/proc`, sysfs, `dumpsys` and Wi-Fi
  channel maths. Most tests live here.
- `lib/model/`, `lib/services/`: settings, ring buffers, the monitor and radio
  controllers, alerts, history and the snapshot builder.
- `lib/platform/`: the method and event channels to Kotlin
  (`native_bridge.dart`) and the normal, Shizuku and root shells
  (`access.dart`).
- `lib/screens/`, `lib/widgets/`: UI and the graph painters.
- `android/app/src/main/kotlin/org/buetow/turbomon/`: the Kotlin side. The
  channel handler (`MainActivity.kt`), metrics readers, Wi-Fi and Bluetooth
  scanning, the background `MonitorService`, the widget, the quick-settings
  tile, Shizuku and root execution, and the snapshot share provider.

The Kotlin code uses only the Android SDK and Shizuku, no androidx.

## Icon

`assets-src/make_icon.py` writes `logo.svg`, `icon-foreground.svg` and
`icon-monochrome.svg`; `assets-src/render.js` renders them with Playwright's
Chromium. Then `flutter pub run flutter_launcher_icons` regenerates the
launcher icons from `logo.png`, `icon-foreground.png` and
`icon-monochrome.png`. Copy a 512 px render to
`fastlane/metadata/android/en-US/images/icon.png`.

## Signing

`android/key.properties` is git-ignored and optional, exactly as in Quicklog:
with it all four of `storeFile`, `storePassword`, `keyAlias`, `keyPassword`
are required; without it release builds use the debug key and say so.
