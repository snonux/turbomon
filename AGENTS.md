# Working on TurboMon

TurboMon is an Android-only Flutter system monitor. It has no internet
permission and must never gain one. Start with [README.md](./README.md) and
the [docs](./docs/).

- `flutter analyze` and `flutter test` must be clean before anything is
  done; changes to Kotlin or `android/` also need
  `flutter build apk --release --split-per-abi`. See
  [docs/building.md](./docs/building.md).
- Logic lives in Dart under `lib/services/` as testable code; parsers get
  tests with real device output in `test/fixtures/`. Kotlin in
  `packages/turbomon_platform/` only bridges Android APIs.
- Shizuku and root are always optional. Every feature must degrade to
  something useful as a normal app and say what is hidden. Privileged
  commands are read-only.
- Releases follow [docs/releasing.md](./docs/releasing.md): bump the build
  counter, write three changelogs per release, and never drop the
  `dependenciesInfo` or `applicationVariants` blocks in
  `android/app/build.gradle.kts`.
- Never create, print or commit signing keys.
- Before a release, go through [docs/testing.md](./docs/testing.md); [docs/phone-testing-handoff.md](./docs/phone-testing-handoff.md) lists what is still untested on a real phone.
- Keep README.md short; detail goes in `docs/`.
