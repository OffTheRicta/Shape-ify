import 'dart:math' as math;

import '../astronomy/sky.dart';
import '../measurement/observation.dart';
import 'layout.dart';

const _radians = math.pi / 180;

class SpatialVector {
  final double x, y, z;
  const SpatialVector(this.x, this.y, this.z);
  static const zero = SpatialVector(0, 0, 0);
  static const pole = SpatialVector(0, 0, 1);

  SpatialVector operator +(SpatialVector b) =>
      SpatialVector(x + b.x, y + b.y, z + b.z);
  SpatialVector operator -(SpatialVector b) => this + b.scale(-1);
  SpatialVector scale(double n) => SpatialVector(x * n, y * n, z * n);
  double dot(SpatialVector b) => x * b.x + y * b.y + z * b.z;
  SpatialVector cross(SpatialVector b) =>
      SpatialVector(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
  double get length => math.sqrt(dot(this));
  SpatialVector get unit => scale(1 / length);
}

class _Frame {
  final SpatialVector east, north, up;
  const _Frame(this.east, this.north, this.up);

  SpatialVector transform(SpatialVector v) =>
      east.scale(v.x) + north.scale(v.y) + up.scale(v.z);

  _Frame rotate(SpatialVector axis, double angle) {
    SpatialVector rotateAxis(SpatialVector v) =>
        v.scale(math.cos(angle)) +
        axis.cross(v).scale(math.sin(angle)) +
        axis.scale(axis.dot(v) * (1 - math.cos(angle)));
    return _Frame(rotateAxis(east), rotateAxis(north), rotateAxis(up));
  }

  factory _Frame.fromRays(SpatialVector first, SpatialVector second) {
    final up = first.cross(second).unit;
    return _Frame(first, up.cross(first), up);
  }
}

class StationOrientation {
  final _Frame _measured;
  final List<double> residualsDeg;
  final bool magnetic;
  final double reportedAngularUncertaintyDeg;
  const StationOrientation._(
    this._measured,
    this.residualsDeg,
    this.magnetic,
    this.reportedAngularUncertaintyDeg,
  );

  SpatialVector get up => _measured.up;
  SpatialVector get east => SpatialVector.pole.cross(up).unit;
  SpatialVector get north => up.cross(east);
  SpatialVector ray(Observation reading) {
    final v = reading.localRay;
    return _measured.transform(SpatialVector(v[0], v[1], v[2]));
  }

  static final _catalog = {
    for (final star in SkyGuide.brightStars) star.name.toLowerCase(): star,
  };

  /// Fits a constant local frame in Earth-fixed equatorial coordinates. For
  /// magnetic readings the fitted horizontal axes describe magnetic east and
  /// north. The rotation pole and fitted up define geographic east and north.
  static StationOrientation? fit(List<Observation> observations) {
    final readings = observations.take(3).toList();
    if (readings.length != 3) return null;
    final reference = readings.first.azimuthReference;
    if (readings.any(
      (o) =>
          o.validate().isNotEmpty ||
          o.azimuthReference != reference ||
          o.simulated != readings.first.simulated,
    )) {
      return null;
    }

    final names = readings.map((o) => o.starId.trim().toLowerCase()).toList();
    if (names.toSet().length != 3 ||
        names.any((name) => !_catalog.containsKey(name))) {
      return null;
    }

    final local = readings.map((o) {
      final v = o.localRay;
      return SpatialVector(v[0], v[1], v[2]);
    }).toList();
    final world = List.generate(3, (i) {
      final star = _catalog[names[i]]!;
      final longitude =
          (star.raHours * 15 - SkyGuide.siderealDeg(readings[i].observedUtc)) *
          _radians;
      final dec = star.decDeg * _radians;
      return SpatialVector(
        math.cos(dec) * math.cos(longitude),
        math.cos(dec) * math.sin(longitude),
        math.sin(dec),
      );
    });

    var first = 0, second = 1;
    var separation = 0.0;
    for (var i = 0; i < 3; i++) {
      for (var j = i + 1; j < 3; j++) {
        final strength = math.min(
          local[i].cross(local[j]).length,
          world[i].cross(world[j]).length,
        );
        if (strength > separation) {
          first = i;
          second = j;
          separation = strength;
        }
      }
    }
    if (separation < .1) return null;
    final source = _Frame.fromRays(local[first], local[second]);
    final target = _Frame.fromRays(world[first], world[second]);
    SpatialVector align(SpatialVector v) => target.transform(
      SpatialVector(source.east.dot(v), source.north.dot(v), source.up.dot(v)),
    );
    var frame = _Frame(
      align(const SpatialVector(1, 0, 0)),
      align(const SpatialVector(0, 1, 0)),
      align(SpatialVector.pole),
    );

    // Minimize the weighted squared differences between unit ray vectors.
    final weights = readings
        .map((o) => 1 / math.pow(math.max(.01, o.angularUncertaintyDeg), 2))
        .toList();
    final totalWeight = weights.reduce((a, b) => a + b);
    for (var step = 0; step < 200; step++) {
      var gradient = SpatialVector.zero;
      for (var i = 0; i < 3; i++) {
        gradient += frame.transform(local[i]).cross(world[i]).scale(weights[i]);
      }
      final angle = gradient.length / totalWeight;
      if (angle < 1e-10) break;
      frame = frame.rotate(gradient.unit, angle);
    }

    if (SpatialVector.pole.cross(frame.up).length < .001) return null;
    final residuals = List.generate(
      3,
      (i) =>
          math.acos(frame.transform(local[i]).dot(world[i]).clamp(-1.0, 1.0)) /
          _radians,
    );
    return StationOrientation._(
      frame,
      List.unmodifiable(residuals),
      reference == 'magnetic',
      readings.map((o) => o.angularUncertaintyDeg).reduce(math.max),
    );
  }
}

class SpatialFit {
  final List<StationOrientation?> orientations;
  final List<SpatialVector>? centresM;
  final double? baselineRmsM;
  final String? unavailableReason;
  const SpatialFit._(
    this.orientations,
    this.centresM,
    this.baselineRmsM,
    this.unavailableReason,
  );

  /// Fit directed GPS baselines in the star-derived local ground frames.
  /// GPS baselines use the WGS84 ellipsoid and reported elevations
  /// to supply length, bearing and slope. This model-dependent reconstruction
  /// estimates station poses and cannot independently test that datum.
  factory SpatialFit.solve(List<StationPoint> stations) {
    final orientations = List<StationOrientation?>.unmodifiable(
      stations.map((s) => StationOrientation.fit(s.observations)),
    );
    SpatialFit unavailable(String reason) =>
        SpatialFit._(orientations, null, null, reason);

    if (stations.length < 2) {
      return unavailable('At least two stations are needed.');
    }
    if (orientations.contains(null)) {
      return unavailable(
        'Each station needs three distinct catalogue readings '
        'with a consistent heading reference and enough angular separation.',
      );
    }
    if (stations.any(
      (s) => s.observation.simulated != stations.first.observation.simulated,
    )) {
      return unavailable(
        'Use an all-demo or all-real session for a spatial fit.',
      );
    }

    // Each endpoint contributes an independent local-frame prediction for
    // the same baseline. The complete graph has a closed-form least-squares
    // solution when the centroid is fixed at zero.
    final centres = List.filled(stations.length, SpatialVector.zero);
    final edges = <(int, int, SpatialVector, SpatialVector)>[];
    for (var i = 0; i < stations.length; i++) {
      for (var j = i + 1; j < stations.length; j++) {
        final a = stations[i].observation, b = stations[j].observation;
        final forward = _baseline(a, b, orientations[i]!);
        final reverse = _baseline(b, a, orientations[j]!);
        if (forward.length <= a.positionUncertaintyM + b.positionUncertaintyM) {
          return unavailable(
            'Two stations are closer than their combined '
            'reported GPS uncertainty.',
          );
        }
        final mean = (forward - reverse).scale(.5);
        centres[i] -= mean;
        centres[j] += mean;
        edges.add((i, j, forward, reverse));
      }
    }

    for (var i = 0; i < centres.length; i++) {
      centres[i] = centres[i].scale(1 / centres.length);
    }
    final extent = centres.map((p) => p.length).reduce(math.max);
    final gpsUncertainty = stations
        .map((s) => s.observation.positionUncertaintyM)
        .reduce(math.max);
    if (extent <= gpsUncertainty / 2) {
      return unavailable('The fitted layout collapses within GPS uncertainty.');
    }
    var squaredError = 0.0;
    for (final (i, j, forward, reverse) in edges) {
      final fitted = centres[j] - centres[i];
      final a = fitted - forward, b = fitted + reverse;
      squaredError += a.dot(a) + b.dot(b);
    }
    return SpatialFit._(
      orientations,
      List.unmodifiable(centres),
      math.sqrt(squaredError / (2 * edges.length)),
      null,
    );
  }

  static SpatialVector _baseline(
    Observation a,
    Observation b,
    StationOrientation orientation,
  ) {
    SpatialVector ecef(Observation o) {
      const semiMajorM = 6378137.0;
      const eccentricitySquared = .0066943799901413165;
      final latitude = o.latitude * _radians;
      final longitude = o.longitude * _radians;
      final sinLat = math.sin(latitude), cosLat = math.cos(latitude);
      final radius =
          semiMajorM / math.sqrt(1 - eccentricitySquared * sinLat * sinLat);
      final horizontal = (radius + o.elevationM) * cosLat;
      return SpatialVector(
        horizontal * math.cos(longitude),
        horizontal * math.sin(longitude),
        (radius * (1 - eccentricitySquared) + o.elevationM) * sinLat,
      );
    }

    final lat = a.latitude * _radians, lon = a.longitude * _radians;
    final datumEast = SpatialVector(-math.sin(lon), math.cos(lon), 0);
    final datumUp = SpatialVector(
      math.cos(lat) * math.cos(lon),
      math.cos(lat) * math.sin(lon),
      math.sin(lat),
    );
    final datumNorth = datumUp.cross(datumEast);
    final delta = ecef(b) - ecef(a);
    return orientation.east.scale(delta.dot(datumEast)) +
        orientation.north.scale(delta.dot(datumNorth)) +
        orientation.up.scale(delta.dot(datumUp));
  }
}
