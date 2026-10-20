import 'dart:math' as math;

class Observation {
  final String id, observer, starId, method, notes;
  final DateTime observedUtc;
  final double latitude, longitude, elevationM, instrumentHeightM;
  final double altitudeDeg, azimuthDeg, angularUncertaintyDeg, positionUncertaintyM;
  final bool nakedEyeConfirmed;
  final bool simulated;
  final String azimuthReference; // 'true' or 'magnetic'

  const Observation({required this.id, required this.observer, required this.starId,
    required this.method, required this.notes, required this.observedUtc,
    required this.latitude, required this.longitude, required this.elevationM,
    required this.instrumentHeightM, required this.altitudeDeg,
    required this.azimuthDeg, required this.angularUncertaintyDeg,
    required this.positionUncertaintyM, required this.nakedEyeConfirmed,
    this.simulated = false,
    this.azimuthReference = 'true'});

  List<String> validate() {
    final errors = <String>[];
    if (id.trim().isEmpty || observer.trim().isEmpty || starId.trim().isEmpty) errors.add('ID, observer and star are required');
    if (observedUtc.isUtc == false) errors.add('Timestamp must be UTC');
    void range(double v, double lo, double hi, String label, {bool exclusiveHi = false}) {
      if (!v.isFinite || v < lo || (exclusiveHi ? v >= hi : v > hi)) errors.add('$label out of range');
    }
    range(latitude, -90, 90, 'Latitude'); range(longitude, -180, 180, 'Longitude');
    range(elevationM, -12000, 100000, 'Elevation');
    range(instrumentHeightM, 0, 1000, 'Instrument height');
    range(altitudeDeg, -90, 90, 'Altitude');
    range(azimuthDeg, 0, 360, 'True azimuth', exclusiveHi: true);
    range(angularUncertaintyDeg, 0.000001, 90, 'Angular uncertainty');
    range(positionUncertaintyM, 0.000001, 1000000, 'Position uncertainty');
    if (!nakedEyeConfirmed && !simulated) errors.add('Naked-eye visibility must be confirmed');
    if (simulated && nakedEyeConfirmed) errors.add('Demo sighting cannot claim naked-eye confirmation');
    if (azimuthReference != 'true' && azimuthReference != 'magnetic') errors.add('Unknown azimuth reference');
    if (method.trim().isEmpty) errors.add('Measurement method is required');
    return errors;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'observer': observer, 'starId': starId, 'method': method,
    'notes': notes, 'observedUtc': observedUtc.toUtc().toIso8601String(),
    'latitude': latitude, 'longitude': longitude, 'elevationM': elevationM,
    'instrumentHeightM': instrumentHeightM, 'altitudeDeg': altitudeDeg,
    'azimuthDeg': azimuthDeg, 'angularUncertaintyDeg': angularUncertaintyDeg,
    'positionUncertaintyM': positionUncertaintyM, 'nakedEyeConfirmed': nakedEyeConfirmed,
    'simulated': simulated,
    'azimuthReference': azimuthReference,
  };

  factory Observation.fromJson(Map<String, dynamic> j) {
    double n(String key) => (j[key] as num).toDouble();
    final o = Observation(id: j['id'] as String, observer: j['observer'] as String,
      starId: j['starId'] as String, method: j['method'] as String,
      notes: j['notes'] as String, observedUtc: DateTime.parse(j['observedUtc'] as String),
      latitude: n('latitude'), longitude: n('longitude'), elevationM: n('elevationM'),
      instrumentHeightM: n('instrumentHeightM'), altitudeDeg: n('altitudeDeg'),
      azimuthDeg: n('azimuthDeg'), angularUncertaintyDeg: n('angularUncertaintyDeg'),
      positionUncertaintyM: n('positionUncertaintyM'), nakedEyeConfirmed: j['nakedEyeConfirmed'] as bool,
      simulated: j['simulated'] == true,
      azimuthReference: j['azimuthReference'] as String? ?? 'true');
    final errors = o.validate();
    if (errors.isNotEmpty) throw FormatException(errors.join('; '));
    return o;
  }

  List<double> get localRay {
    final a = azimuthDeg * math.pi / 180, h = altitudeDeg * math.pi / 180;
    return [math.cos(h) * math.sin(a), math.cos(h) * math.cos(a), math.sin(h)];
  }
}
