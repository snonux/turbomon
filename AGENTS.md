# Working on TurboMon

TurboMon is an Android-only Flutter system monitor. It has no internet
permission and must never gain one. Start with [README.md](./README.md) and
the [docs](./docs/).

- Before calling anything done, `flutter analyze` and `flutter test` must be
  clean; for changes under `android/`, also build a release APK
  (`flutter build apk --release --split-per-abi`). See
  [docs/building.md](./docs/building.md).
- Parsing belongs in `lib/parsers/` as pure functions with tests, using real
  sample output from devices.
- Kotlin uses the Android SDK and Shizuku only, no androidx.
- Elevated access (Shizuku, root) is always optional. Every feature must
  degrade to something useful as a normal app, and say what is hidden.
- Releases follow [docs/releasing.md](./docs/releasing.md); the traps are the
  same as Quicklog's (bump the build counter, three changelogs per release,
  never drop the `dependenciesInfo` or `applicationVariants` blocks).
- Never create, print or commit signing keys.
- Before a release, go through [docs/testing.md](./docs/testing.md) on a device.
- Keep README.md short; detail goes in `docs/`.
