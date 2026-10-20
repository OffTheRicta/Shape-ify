import 'package:flutter_test/flutter_test.dart';
import 'package:roundhound/astronomy/sky.dart';
import 'package:roundhound/measurement/device_orientation.dart';

void main() {
  test('sidereal angle near J2000 reference', () {
    expect(SkyGuide.siderealDeg(DateTime.utc(2000,1,1,12)),
        closeTo(280.46, 0.2));
  });
  test('Polaris is near the north horizon from equator', () {
    const polaris = GuideStar('Polaris', 2.5303, 89.264, 2);
    final p = SkyGuide.horizontal(polaris, 0, 0, DateTime.utc(2026,9,24));
    expect(p.altitudeDeg.abs(), lessThan(1));
    expect(SkyGuide.angularDelta(p.azimuthDeg, 0).abs(), lessThan(1));
  });
  test('rear camera vector gives north at horizon', () {
    final reading = DeviceOrientation.rearCamera(
        const Axis3(0,1,0), const Axis3(0,0,-1))!;
    expect(reading.magneticAzimuthDeg, closeTo(0, 0.00001));
    expect(reading.altitudeDeg, closeTo(0, 0.00001));
  });
  test('refuses degenerate magnetic sensor vectors', () {
    expect(DeviceOrientation.rearCamera(
        const Axis3(0,0,1), const Axis3(0,0,1)), isNull);
  });
}
