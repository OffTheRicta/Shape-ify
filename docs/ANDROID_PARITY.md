# Android build parity

The iOS simulator build and Android CI now use the same Flutter sources and `pubspec.yaml` version `0.1.0+38`. The Android application ID is `shapeify.roundhound.info`. The Android project, launcher icons, camera/location permissions, and dark launch styling are checked in.

## Installable test APK

Open **Actions → Shape-ify Android parity build → latest green run → Artifacts**. Download `shapeify-android-0.1.0+38-debug` and extract `app-debug.apk`. This is signed with a **debug** key. It is suitable for emulator and direct installation testing, but it cannot update an existing Play-installed app with the same application ID because that app has a different signature. Use an emulator, or first back up any data you care about before uninstalling a Play-installed copy.

CI builds the APK with `SHAPEIFY_DEMO=false` and `SHAPEIFY_RELAY_URL=https://relay.roundhound.info`.

## Signed Play update

The existing private upload keystore is intentionally absent from GitHub. For a signed AAB on your Windows machine, use the checked-in Android project and copy your **existing** `android/key.properties` and upload keystore into the checkout. The four required property names are `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. `storeFile` must resolve to the existing keystore. Never generate a new upload key for an update or commit the signing files.

Run from the repository root:

```bash
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release \
  --dart-define=SHAPEIFY_DEMO=false \
  --dart-define=SHAPEIFY_RELAY_URL=https://relay.roundhound.info
```

The output is `build/app/outputs/bundle/release/app-release.aab`. Verify it is signed with your existing upload key before sending it to Play. The signed Play build has **not** been produced in CI because the key is only on your computer. The debug APK is a test artifact, not a Play submission.

When switching back to a local clone that predates this change, use a fresh clone or inspect your old untracked `android/` directory before pulling; Git will refuse to overwrite untracked files.
