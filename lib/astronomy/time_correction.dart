import 'dart:math' as math;
import '../measurement/observation.dart';
import 'sky.dart';

/// Guidance residual in the catalog's Earth-rotation/reference-coordinate
/// model. This is a quality check, never an independent surface fit.
class CatalogResidual {
  final double eastDeg, upDeg;
  const CatalogResidual(this.eastDeg, this.upDeg);
  double get magnitudeDeg => math.sqrt(eastDeg * eastDeg + upDeg * upDeg);

  static CatalogResidual? forObservation(Observation reading) {
    if (reading.azimuthReference != 'true' || reading.simulated) return null;
    final stars = SkyGuide.brightStars.where((s) => s.name == reading.starId);
    if (stars.isEmpty) return null;
    final predicted = SkyGuide.horizontal(stars.first, reading.latitude,
        reading.longitude, reading.observedUtc);
    return CatalogResidual(
      SkyGuide.angularDelta(reading.azimuthDeg, predicted.azimuthDeg) *
          math.cos(predicted.altitudeDeg * math.pi / 180),
      reading.altitudeDeg - predicted.altitudeDeg);
  }
}
