import 'dart:math' as math;
import '../measurement/observation.dart';
import 'ray_geometry.dart';
import '../astronomy/time_correction.dart';

class PairComparison {
  final Observation a, b;
  final double raySeparationDeg, altitudeDifferenceDeg, baselineM;
  final bool baselineApproximate, magneticReference;
  final double? modelDependentResidualDifferenceDeg;
  const PairComparison(this.a, this.b, this.raySeparationDeg,
      this.altitudeDifferenceDeg, this.baselineM, this.baselineApproximate,
      this.magneticReference, this.modelDependentResidualDifferenceDeg);
}

class ComparisonSolver {
  static PairComparison? compare(Observation a, Observation b) {
    if (a.id == b.id || a.observer.trim().toLowerCase() == b.observer.trim().toLowerCase() ||
        a.starId.trim().toLowerCase() != b.starId.trim().toLowerCase()) {
      return null;
    }
    final separation = localRaySeparationDeg(
        a.altitudeDeg, a.azimuthDeg, b.altitudeDeg, b.azimuthDeg);
    // Short-range WGS84 tangent approximation used solely to label a baseline.
    final phi = (a.latitude + b.latitude) * math.pi / 360;
    final north = (b.latitude - a.latitude) * math.pi / 180 * 6378137;
    final east = (b.longitude - a.longitude) * math.pi / 180 * 6378137 * math.cos(phi);
    final baseline = math.sqrt(east*east + north*north);
    final ra = CatalogResidual.forObservation(a);
    final rb = CatalogResidual.forObservation(b);
    final delta = ra == null || rb == null ? null :
      math.sqrt(math.pow(ra.eastDeg - rb.eastDeg, 2) +
        math.pow(ra.upDeg - rb.upDeg, 2));
    return PairComparison(a, b, separation, b.altitudeDeg-a.altitudeDeg,
      baseline, baseline > 100000,
      a.azimuthReference == 'magnetic' || b.azimuthReference == 'magnetic',
      delta);
  }

  static List<PairComparison> all(Iterable<Observation> observations) {
    final list = observations.toList();
    return [for (var i=0; i<list.length; i++) for (var j=i+1; j<list.length; j++)
      if (compare(list[i], list[j]) case final result?) result];
  }
}
