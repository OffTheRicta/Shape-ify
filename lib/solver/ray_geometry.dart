import 'dart:math' as math;

/// Numerical angle between two reported rays in nominally parallel local axes.
/// A physical interpretation requires independently established common axes.
double localRaySeparationDeg(
    double altitudeA, double azimuthA, double altitudeB, double azimuthB) {
  final h1 = altitudeA * math.pi / 180;
  final h2 = altitudeB * math.pi / 180;
  final da = (azimuthA - azimuthB) * math.pi / 180;
  final dot = math.sin(h1) * math.sin(h2) +
      math.cos(h1) * math.cos(h2) * math.cos(da);
  return math.acos(dot.clamp(-1.0, 1.0)) * 180 / math.pi;
}
