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
  final double? bearingRmsDeg;
  final String? unavailableReason;
  const SpatialFit._(
    this.orientations,
    this.centresM,
    this.baselineRmsM,
    this.bearingRmsDeg,
    this.unavailableReason,
  );

  /// Fit free station centres from model-dependent GPS chord lengths and
  /// horizontal bearings in the independently fitted station frames.
  factory SpatialFit.solve(List<StationPoint> stations) {
    final orientations = List<StationOrientation?>.unmodifiable(
      stations.map((s) => StationOrientation.fit(s.observations)),
    );
    SpatialFit unavailable(String reason) =>
        SpatialFit._(orientations, null, null, null, reason);

    if (stations.length < 3) {
      return unavailable('At least three stations are needed for a 3D fit.');
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

    final baselines = <_Baseline>[];
    final seed = List.filled(stations.length, SpatialVector.zero);
    for (var i = 0; i < stations.length; i++) {
      for (var j = i + 1; j < stations.length; j++) {
        final a = stations[i].observation;
        final b = stations[j].observation;
        final chord = _ecef(b) - _ecef(a);
        final length = chord.length;
        if (length <= a.positionUncertaintyM + b.positionUncertaintyM) {
          return unavailable(
            'Two stations are closer than their combined reported GPS uncertainty.',
          );
        }
        final forward = _bearing(a, chord, orientations[i]!);
        final reverse = _bearing(b, chord.scale(-1), orientations[j]!);
        if (forward == null || reverse == null) {
          return unavailable(
            'A GPS baseline has no reliable horizontal bearing.',
          );
        }
        baselines.add(
          _Baseline(
            i,
            j,
            length,
            forward,
            reverse,
            orientations[i]!.up,
            orientations[j]!.up,
          ),
        );
        // Start from the average horizontal prediction. Vertical displacement
        // is a free variable and the seed does not use GPS-derived slope.
        final delta = (forward - reverse).scale(length / 2 / stations.length);
        seed[i] -= delta;
        seed[j] += delta;
      }
    }

    final scale = baselines.map((b) => b.length).reduce(math.max);
    final origin = seed.first;
    var centres = [for (final p in seed) (p - origin).scale(1 / scale)];
    final size = (centres.length - 1) * 3;
    var damping = .001;
    var system = _FitSystem(size, centres, baselines, scale);
    for (var iteration = 0; iteration < 100; iteration++) {
      final step = system.step(damping);
      if (step == null) break;
      final next = [
        SpatialVector.zero,
        for (var i = 0; i < size; i += 3)
          centres[i ~/ 3 + 1] +
              SpatialVector(step[i], step[i + 1], step[i + 2]),
      ];
      final trial = _FitSystem(size, next, baselines, scale);
      if (trial.error < system.error) {
        centres = next;
        final improvement = system.error - trial.error;
        system = trial;
        damping = math.max(1e-10, damping / 3);
        if (improvement < 1e-19) break;
      } else {
        damping *= 10;
        if (damping > 1e8) break;
      }
    }
    if (!system.resolvesAllPositions) {
      return unavailable(
        'The lengths and bearings leave some station positions unresolved.',
      );
    }

    var squaredLengthError = 0.0;
    var squaredBearingError = 0.0;
    for (final baseline in baselines) {
      final delta = (centres[baseline.j] - centres[baseline.i]).scale(scale);
      final lengthError = delta.length - baseline.length;
      squaredLengthError += lengthError * lengthError;
      final a = baseline.bearingError(delta, reverse: false);
      final b = baseline.bearingError(delta.scale(-1), reverse: true);
      if (a == null || b == null || a >= 90 || b >= 90) {
        return unavailable(
          'The fitted baselines do not resolve the GPS bearings.',
        );
      }
      squaredBearingError += a * a + b * b;
    }
    final centroid = centres.reduce((a, b) => a + b).scale(1 / centres.length);
    return SpatialFit._(
      orientations,
      List.unmodifiable(centres.map((p) => (p - centroid).scale(scale))),
      math.sqrt(squaredLengthError / baselines.length),
      math.sqrt(squaredBearingError / (2 * baselines.length)),
      null,
    );
  }

  static SpatialVector _ecef(Observation o) {
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

  static SpatialVector? _bearing(
    Observation origin,
    SpatialVector datumChord,
    StationOrientation orientation,
  ) {
    final lat = origin.latitude * _radians;
    final lon = origin.longitude * _radians;
    final east = SpatialVector(-math.sin(lon), math.cos(lon), 0);
    final up = SpatialVector(
      math.cos(lat) * math.cos(lon),
      math.cos(lat) * math.sin(lon),
      math.sin(lat),
    );
    final north = up.cross(east);
    final world =
        orientation.east.scale(datumChord.dot(east)) +
        orientation.north.scale(datumChord.dot(north));
    return world.length <= origin.positionUncertaintyM ? null : world.unit;
  }
}

class _Baseline {
  final int i, j;
  final double length;
  final SpatialVector forward, reverse, upAtI, upAtJ;

  const _Baseline(
    this.i,
    this.j,
    this.length,
    this.forward,
    this.reverse,
    this.upAtI,
    this.upAtJ,
  );

  double? bearingError(SpatialVector delta, {required bool reverse}) {
    final up = reverse ? upAtJ : upAtI;
    final target = reverse ? this.reverse : forward;
    final horizontal = delta - up.scale(up.dot(delta));
    if (horizontal.length < length * 1e-8) return null;
    return math.atan2(
          up.cross(target).dot(horizontal).abs(),
          target.dot(horizontal),
        ) /
        _radians;
  }
}

/// Normal equations for the distance and horizontal bearing residuals.
/// The first centre fixes translation. Distance fixes the scale, and the
/// star-derived frames supply world axes. Rank is a local conditioning check.
class _FitSystem {
  final List<List<double>> normal;
  final List<double> gradient;
  double error = 0;

  _FitSystem(
    int size,
    List<SpatialVector> centres,
    List<_Baseline> baselines,
    double scale,
  ) : normal = List.generate(size, (_) => List.filled(size, 0.0)),
      gradient = List.filled(size, 0.0) {
    for (final b in baselines) {
      final delta = centres[b.j] - centres[b.i];
      final length = b.length / scale;
      final weight = 1 / length;
      if (delta.length > 1e-12) {
        _add(
          b.i,
          b.j,
          delta.unit.scale(weight),
          (delta.length - length) * weight,
        );
      }
      final forwardNormal = b.upAtI.cross(b.forward).scale(weight);
      final reverseNormal = b.upAtJ.cross(b.reverse).scale(weight);
      _add(b.i, b.j, forwardNormal, delta.dot(forwardNormal));
      _add(b.i, b.j, reverseNormal, delta.dot(reverseNormal));
      final forward = delta.dot(b.forward);
      final reverse = -delta.dot(b.reverse);
      if (forward < 0) {
        _add(b.i, b.j, b.forward.scale(weight), forward * weight);
      }
      if (reverse < 0) {
        _add(b.i, b.j, b.reverse.scale(-weight), reverse * weight);
      }
    }
  }

  void _add(int i, int j, SpatialVector derivative, double residual) {
    error += residual * residual;
    final values = [derivative.x, derivative.y, derivative.z];
    final terms = [
      for (var axis = 0; axis < 3; axis++) ...[
        if (i > 0) (3 * (i - 1) + axis, -values[axis]),
        (3 * (j - 1) + axis, values[axis]),
      ],
    ];
    for (final (row, a) in terms) {
      gradient[row] += a * residual;
      for (final (column, b) in terms) {
        normal[row][column] += a * b;
      }
    }
  }

  bool get resolvesAllPositions => step(0, tolerance: 1e-9) != null;

  List<double>? step(double damping, {double tolerance = 1e-15}) {
    final count = gradient.length;
    final rows = [
      for (var i = 0; i < count; i++) [...normal[i], -gradient[i]],
    ];
    var largestDiagonal = 0.0;
    for (var i = 0; i < count; i++) {
      largestDiagonal = math.max(largestDiagonal, rows[i][i]);
      rows[i][i] += damping * math.max(1, rows[i][i]);
    }

    for (var column = 0; column < count; column++) {
      var pivot = column;
      for (var row = column + 1; row < count; row++) {
        if (rows[row][column].abs() > rows[pivot][column].abs()) pivot = row;
      }
      if (rows[pivot][column].abs() <= tolerance * largestDiagonal) return null;
      final swap = rows[column];
      rows[column] = rows[pivot];
      rows[pivot] = swap;
      for (var row = column + 1; row < count; row++) {
        final factor = rows[row][column] / rows[column][column];
        for (var k = column + 1; k <= count; k++) {
          rows[row][k] -= factor * rows[column][k];
        }
      }
    }

    final result = List.filled(count, 0.0);
    for (var row = count - 1; row >= 0; row--) {
      var value = rows[row][count];
      for (var k = row + 1; k < count; k++) {
        value -= rows[row][k] * result[k];
      }
      result[row] = value / rows[row][row];
    }
    return result;
  }
}
