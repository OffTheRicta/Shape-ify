#!/usr/bin/env python3
"""Configure a generated Flutter Android host for Shape-ify test builds."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"

gradle = GRADLE.read_text()
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
MANIFEST.write_text(manifest)

print(f"Android ID: shapeify.roundhound.info; activity: {package_match.group(1)}.MainActivity")
