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

These follow snonux/fdroid's
[onboarding guide](https://github.com/snonux/fdroid/blob/main/docs/onboarding-flutter-app.md);
steps 1 to 3 are Paul's, because agents cannot write workflow files or
handle keys. In fish, from the repo root:

1. **Signing key**, kept outside the repo, with a backup in
   `~/.foostore-export/`. Losing it means existing installs can never be
   updated.

   ```fish
   mkdir -p ~/.config/turbomon
   set pw (openssl rand -hex 16)
   keytool -genkeypair -noprompt -keystore ~/.config/turbomon/release.jks -storetype PKCS12 \
     -alias turbomon -keyalg RSA -keysize 4096 -validity 36500 \
     -dname "CN=TurboMon" -storepass $pw -keypass $pw
   printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=turbomon\nkeyPassword=%s\n' \
     ~/.config/turbomon/release.jks $pw $pw > android/key.properties
   chmod 600 ~/.config/turbomon/release.jks android/key.properties
   ```

2. **Workflow.** Move the staged workflow into place:

   ```fish
   git checkout main; and git pull
   mkdir -p .github/workflows; and git mv ci/workflows/release.yml .github/workflows/
   git commit -m "Enable release workflow"; and git push
   ```

3. **Secrets** for the workflow; `FDROID_DISPATCH_TOKEN` (optional) makes
   snonux/fdroid refresh at once instead of within six hours.

   ```fish
   function get; sed -n "s/^$argv[1]=//p" android/key.properties; end
   base64 -w0 (get storeFile) | gh secret set ANDROID_KEYSTORE
   gh secret set ANDROID_KEY_ALIAS --body (get keyAlias)
   gh secret set ANDROID_KEYSTORE_PASSWORD --body (get storePassword)
   gh secret set ANDROID_KEY_PASSWORD --body (get keyPassword)
   gh secret list
   ```

4. **Register the app** in snonux/fdroid: `apps.yml`, the metadata file
   `fdroid/metadata/org.buetow.turbomon.yml`, the README's app list and the
   tables in its `docs/releasing-apps.md` and `docs/release-check.md`.

Then release by starting the workflow (an agent can do this too; it creates
the tag):

```fish
gh workflow run release.yml -R snonux/turbomon --ref main -f tag=v0.1.0
gh run watch -R snonux/turbomon
```

## Store text

F-Droid takes title, summary, description, icon, screenshots and changelogs
from `fastlane/metadata/android/en-US/`. The summary is capped at 80
characters with no trailing period.
