import '../measurement/observation.dart';

/// A station is identified by its observer label. Guided capture assigns each
/// phone a stable station label; manual entries should use a distinct label per site.
/// Layout is stable regardless of the order in which peer JSON arrives.
class StationLayout {
  static List<StationPoint> arrange(Iterable<Observation> observations) {
    final byStation = <String, List<Observation>>{};
    for (final observation in observations) {
      final key = observation.observer.trim().toLowerCase();
      byStation.putIfAbsent(key, () => []).add(observation);
    }
    final keys = byStation.keys.toList()..sort();
    return [
      for (var i = 0; i < keys.length; i++)
        StationPoint(
          List<Observation>.unmodifiable(byStation[keys[i]]!
            ..sort((a, b) {
              final time = a.observedUtc.compareTo(b.observedUtc);
              return time != 0 ? time : a.id.compareTo(b.id);
            })),
          i % 3,
          i ~/ 3,
        ),
    ];
  }
}

/// Rendering coordinates only. These are deliberately independent of the
/// solver: the transition cannot be mistaken for inferred ground geometry.
class AssemblyLayout {
  static bool ready(Iterable<StationPoint> points, List<String>? targetStars,
      int? expectedSites, Iterable<String> excludedStations) {
    if (targetStars == null || expectedSites == null || expectedSites < 2 ||
        targetStars.length != 3) {
      return false;
    }
    final excluded = excludedStations.toSet();
    final completed = points.where((point) =>
        !excluded.contains(point.observation.observer) &&
        targetStars.every((star) =>
            point.observations.any((reading) => reading.starId == star)));
    return completed.length >= expectedSites;
  }

  static LayoutPosition staging(int index, double width) =>
      LayoutPosition(width / 2 + ((index % 3) - 1) * 104,
          99 + (index ~/ 3) * 128);

  static LayoutPosition assembled(int index, int count, double width,
      double height) {
    final col = index % 3;
    final row = index ~/ 3;
    final rows = (count / 3).ceil();
    return LayoutPosition(width / 2 + (col - 1) * 82 + row * 11,
        height / 2 + (row - (rows - 1) / 2) * 76 + (col.isOdd ? -19 : 19));
  }
}

class LayoutPosition {
  final double x, y;
  const LayoutPosition(this.x, this.y);
}

class StationPoint {
  final List<Observation> observations;
  final int column, row;
  const StationPoint(this.observations, this.column, this.row);

  Observation get observation => observations.first;
}
