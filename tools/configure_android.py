#!/usr/bin/env python3
"""Configure a generated Flutter Android host for Shape-ify test builds."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"

gradle = GRADLE.read_text()
if "val keystorePropertiesFile" not in gradle:
    gradle = "import java.util.Properties\n\n" + gradle
    gradle = gradle.replace(
        "android {",
        'val keystorePropertiesFile = rootProject.file("key.properties")\n'
        'val keystoreProperties = Properties().apply {\n'
        '    if (keystorePropertiesFile.exists()) {\n'
        '        keystorePropertiesFile.inputStream().use { load(it) }\n'
        '    }\n'
        '}\n\nandroid {',
        1,
    )
    gradle = gradle.replace(
        "    buildTypes {",
        '    signingConfigs {\n'
        '        if (keystorePropertiesFile.exists()) {\n'
        '            create("release") {\n'
        '                keyAlias = requireNotNull(keystoreProperties.getProperty("keyAlias"))\n'
        '                keyPassword = requireNotNull(keystoreProperties.getProperty("keyPassword"))\n'
        '                storeFile = file(requireNotNull(keystoreProperties.getProperty("storeFile")))\n'
        '                storePassword = requireNotNull(keystoreProperties.getProperty("storePassword"))\n'
        '            }\n'
        '        }\n'
        '    }\n\n'
        '    buildTypes {',
        1,
    )
    gradle = gradle.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'if (keystorePropertiesFile.exists()) {\n'
        '                signingConfig = signingConfigs.getByName("release")\n'
        '            }',
        1,
    )
    if "signingConfigs.getByName(\"debug\")" in gradle:
        raise SystemExit("Refusing to sign a release with the debug key")
gradle, count = re.subn(
    r'(?m)^(\s*applicationId\s*=\s*)"[^"]+"',
    r'\1"shapeify.roundhound.info"',
    gradle,
    count=1,
)
if count != 1:
    raise SystemExit("Expected one applicationId in android/app/build.gradle.kts")
GRADLE.write_text(gradle)

activities = list((ROOT / "android/app/src/main/kotlin").rglob("MainActivity.kt"))
if len(activities) != 1:
    raise SystemExit(f"Expected one MainActivity.kt, found {len(activities)}")
package_match = re.search(r"(?m)^package\s+([A-Za-z0-9_.]+)\s*$", activities[0].read_text())
if package_match is None:
    raise SystemExit("Cannot determine generated MainActivity package")

manifest = MANIFEST.read_text()
permissions = (
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.CAMERA" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
    '<uses-feature android:name="android.hardware.camera" android:required="false" />',
)
if "<manifest" not in manifest:
    raise SystemExit("Cannot find Android manifest root")
for item in permissions:
    if item not in manifest:
        if "<application" not in manifest:
            raise SystemExit("Cannot find Android application element")
        manifest = manifest.replace("<application", f"{item}\n    <application", 1)
manifest, count = re.subn(
    r'android:label="[^"]+"', 'android:label="Shape-ify"', manifest, count=1
)
if count != 1:
    raise SystemExit("Cannot find generated Android app label")
manifest = manifest.replace(
    'android:name=".MainActivity"',
    f'android:name="{package_match.group(1)}.MainActivity"',
)
if f'{package_match.group(1)}.MainActivity' not in manifest:
    raise SystemExit("Cannot configure generated MainActivity")
if 'android:roundIcon=' not in manifest:
    manifest = manifest.replace(
        'android:icon="@mipmap/ic_launcher"',
        'android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher_round"',
        1,
    )
MANIFEST.write_text(manifest)

for directory in ("values", "values-night"):
    path = ROOT / "android/app/src/main/res" / directory / "styles.xml"
    styles = path.read_text().replace("Theme.Light.NoTitleBar", "Theme.NoTitleBar")
    styles = styles.replace("?android:colorBackground", "@android:color/black")
    path.write_text(styles)
for directory in ("drawable", "drawable-v21"):
    path = ROOT / "android/app/src/main/res" / directory / "launch_background.xml"
    path.write_text(path.read_text().replace("@android:color/white", "@android:color/black"))

print(f"Android ID: shapeify.roundhound.info; activity: {package_match.group(1)}.MainActivity")
