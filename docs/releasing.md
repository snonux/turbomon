# Releasing

TurboMon ships through [snonux/fdroid](https://github.com/snonux/fdroid), the
same way as Quicklog: a `vX.Y.Z` tag builds signed per-ABI APKs on GitHub
Actions and attaches them to a GitHub release, and the F-Droid repo picks
them up from there. Quicklog's
[AGENTS.md](https://github.com/snonux/quicklog/blob/main/AGENTS.md#releasing)
explains every reproducibility trap; the short version is below.

## Every release

1. Bump `version:` in `pubspec.yaml` (`<semver>+<counter>`). Forgetting the
   counter means F-Droid silently never ships the release.
2. Write the changelog three times, once per ABI version code
   (`counter * 10 + abi`): counter 1 gives `11.txt`, `12.txt`, `13.txt` in
   `fastlane/metadata/android/en-US/changelogs/`. 500 characters max.
3. Keep `.flutter-version` current.
4. Go through [testing.md](./testing.md) with the release APK.
5. Tag and push `vX.Y.Z`, or run the *Release* workflow by hand with the tag
   as input (it creates the tag if it does not exist).

The workflow checks that the tag matches `pubspec.yaml`, builds from
`/tmp/build` against `/opt/android-sdk`, refuses debug-signed APKs and
uploads `app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk` and
`app-x86_64-release.apk`.

## One-time setup

1. **Workflow.** Copy `ci/workflows/release.yml` to
   `.github/workflows/release.yml` (it is staged under `ci/` because the
   agent that wrote it cannot push workflow files).
2. **Signing key.** Create `keys/turbomon-release.jks` and keep an offline
   backup: losing it means existing installs can never be updated. `keys/`,
   `*.jks` and `android/key.properties` are git-ignored.

   ```fish
   mkdir -p keys
   keytool -genkeypair -v -keystore keys/turbomon-release.jks -alias turbomon \
       -keyalg RSA -keysize 4096 -validity 10000
   ```

3. **Secrets** on the GitHub repo: `ANDROID_KEYSTORE` (the `.jks`, base64),
   `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
   and optionally `FDROID_DISPATCH_TOKEN` so snonux/fdroid refreshes at once
   instead of within six hours.

   ```fish
   base64 -w0 keys/turbomon-release.jks | gh secret set ANDROID_KEYSTORE -R snonux/turbomon
   gh secret set ANDROID_KEY_ALIAS -R snonux/turbomon --body turbomon
   gh secret set ANDROID_KEYSTORE_PASSWORD -R snonux/turbomon
   gh secret set ANDROID_KEY_PASSWORD -R snonux/turbomon
   ```

4. **Register the app** in snonux/fdroid: an entry in `apps.yml`, the metadata
   file `fdroid/metadata/org.buetow.turbomon.yml`, and a line in its README
   and `docs/releasing-apps.md`.

## Store text

F-Droid takes title, summary, description, icon, screenshots and changelogs
from `fastlane/metadata/android/en-US/`. The summary is capped at 80
characters with no trailing period.
