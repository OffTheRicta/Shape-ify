import 'dart:math' as math;
import '../astronomy/sky.dart';

class Axis3 {
  final double x, y, z;
  const Axis3(this.x, this.y, this.z);
  Axis3 cross(Axis3 b) => Axis3(y * b.z - z * b.y,
      z * b.x - x * b.z, x * b.y - y * b.x);
  double dot(Axis3 b) => x * b.x + y * b.y + z * b.z;
  double get length => math.sqrt(dot(this));
  Axis3? get normalized => length < 1e-8 || !length.isFinite
      ? null : Axis3(x / length, y / length, z / length);
}

class DeviceDirection {
  final double magneticAzimuthDeg, altitudeDeg;
  const DeviceDirection(this.magneticAzimuthDeg, this.altitudeDeg);
}

/// Device coordinates x right, y top, z outward from front display.
/// The rear camera points along -z. North here is MAGNETIC north.
class DeviceOrientation {
  static DeviceDirection? rearCamera(Axis3? accelerometer, Axis3? magnetometer) {
    final up = accelerometer?.normalized;
    if (up == null || magnetometer == null) return null;
    final east = magnetometer.cross(up).normalized;
    if (east == null) return null;
    final north = up.cross(east).normalized;
    if (north == null) return null;
    const rear = Axis3(0, 0, -1);
    final altitude = math.asin(rear.dot(up).clamp(-1.0, 1.0)) * 180 / math.pi;
    final azimuth = SkyGuide.wrap(
        math.atan2(rear.dot(east), rear.dot(north)) * 180 / math.pi);
    return DeviceDirection(azimuth, altitude);
  }
}
