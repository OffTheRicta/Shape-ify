import '../measurement/observation.dart';

/// Human attestation is required. Geometry alone cannot verify optical visibility.
class Visibility {
  static bool eligible(Observation o) => o.nakedEyeConfirmed && o.altitudeDeg > 0;
  static String status(Observation o) => eligible(o)
      ? 'Observer confirmed naked-eye sighting above horizon'
      : 'Not eligible: requires an above-horizon naked-eye sighting';
}
