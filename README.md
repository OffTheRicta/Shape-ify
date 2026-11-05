# Shape-ify v0.1.0+38

Shape-ify is a Flutter Android/iPhone project for comparing observer ground orientations using measurements of visible stars. Android and iOS build from the same `lib/`, `test/`, and `pubspec.yaml` sources. The application ID on Android is `shapeify.roundhound.info`.

## Current build status

- Android: the checked-in Android host builds an **installable debug APK** in GitHub Actions. The `Shape-ify Android parity build` workflow runs `flutter analyze`, `flutter test`, and `flutter build apk --debug`.
- iOS: the `Shape-ify iOS Simulator` workflow builds the shared Flutter source for simulator testing. An iOS simulator build is **not** a TestFlight release.
- The startup regression test in `test/widget_test.dart` checks that Create Group and Join Group appear automatically after the introduction, without blocking on location.
- The CI build uses `SHAPEIFY_DEMO=false` and `SHAPEIFY_RELAY_URL=https://relay.roundhound.info`.

See [Android parity and signing instructions](docs/ANDROID_PARITY.md) before using the Android build on a device.

## Android release caution

The CI APK is **debug-signed**. It cannot update the installed Play Store app. A Play Store update needs the **existing upload keystore**, the original Android native settings checked against this project, a release AAB, and a version code accepted by Google Play. Keystores and `android/key.properties` must remain local and out of GitHub.

The previously used original Android project archive has **not yet been compared** with this generated, checked-in Android host. Treat platform parity as verified at the Flutter source/build level, **not** as proof that every original Android-native configuration was preserved. Do not overwrite an older local `android/` directory without backing it up or comparing it first.

## Experiment scope

Participants create or join a real group, plan three visible stars, and record rear-camera measurements. Group data are exchanged through the configured relay so each phone can calculate result visualizations. The star planning approach is described in [STAR_PLANNING.md](STAR_PLANNING.md).

Flat and globe plots are visualizations of recorded orientations; they are not a validated surface fit. The ground-angle solver does not assume Earth curvature.
