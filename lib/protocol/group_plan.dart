import 'dart:convert';

/// Rounded position shared voluntarily with the organizer for sky planning.
class ParticipantSite {
  final String station;
  final double latitude, longitude;
  final DateTime reportedUtc;

  const ParticipantSite(this.station, this.latitude, this.longitude,
      this.reportedUtc);

  factory ParticipantSite.rounded(
      String station, double latitude, double longitude, DateTime time) {
    double round(double value) => (value * 100).round() / 100;
    return ParticipantSite(station, round(latitude), round(longitude),
        time.toUtc());
  }

  Map<String, dynamic> toJson() => {
    'station': station, 'latitude': latitude, 'longitude': longitude,
    'reportedUtc': reportedUtc.toIso8601String(),
  };

  factory ParticipantSite.fromJson(Map<String, dynamic> json) {
    final site = ParticipantSite(
      json['station'] as String,
      (json['latitude'] as num).toDouble(),
      (json['longitude'] as num).toDouble(),
      DateTime.parse(json['reportedUtc'] as String),
    );
    if (site.station.trim().isEmpty || !site.latitude.isFinite ||
        !site.longitude.isFinite || site.latitude.abs() > 90 ||
        site.longitude.abs() > 180 || !site.reportedUtc.isUtc) {
      throw const FormatException('Invalid participant location');
    }
    return site;
  }
}

/// A common UTC window and three star names; contains no participant positions.
class SharedPlan {
  final List<String> stars;
  final List<String> excludedStations;
  final DateTime targetUtc, createdUtc;
  final int siteCount;
  final bool distributed;
  final DateTime? deadlineUtc;
  final List<SiteWindow> windows;

  SharedPlan(Iterable<String> stars, this.targetUtc, this.createdUtc,
      this.siteCount, {Iterable<String> excludedStations = const [],
        this.distributed = false, this.deadlineUtc,
        Iterable<SiteWindow> windows = const []})
      : stars = List.unmodifiable(stars),
        excludedStations = List.unmodifiable(excludedStations),
        windows = List.unmodifiable(windows) {
    if (this.stars.length != 3 || this.stars.toSet().length != 3 ||
        this.stars.any((name) => name.trim().isEmpty) ||
        !targetUtc.isUtc || !createdUtc.isUtc || siteCount < 2 ||
        this.excludedStations.any((name) => name.trim().isEmpty) ||
        this.excludedStations.toSet().length != this.excludedStations.length ||
        (distributed && (deadlineUtc == null || this.windows.isEmpty))) {
      throw const FormatException('Invalid shared sky plan');
    }
  }

  Map<String, dynamic> toJson() => {
    'stars': stars, 'targetUtc': targetUtc.toIso8601String(),
    'createdUtc': createdUtc.toIso8601String(), 'siteCount': siteCount,
    'excludedStations': excludedStations,
    if (distributed) 'distributed': true,
    if (deadlineUtc != null) 'deadlineUtc': deadlineUtc!.toIso8601String(),
    if (windows.isNotEmpty) 'window': windows.map((w) => w.toJson()).toList(),
  };

  factory SharedPlan.fromJson(Map<String, dynamic> json) => SharedPlan(
    (json['stars'] as List).cast<String>(),
    DateTime.parse(json['targetUtc'] as String),
    DateTime.parse(json['createdUtc'] as String),
    json['siteCount'] as int,
    excludedStations: (json['excludedStations'] as List? ?? const [])
        .cast<String>(),
    distributed: json['distributed'] == true,
    deadlineUtc: json['deadlineUtc'] == null ? null :
      DateTime.parse(json['deadlineUtc'] as String),
    windows: (json['window'] as List? ?? const []).map((w) =>
      SiteWindow.fromJson(Map<String, dynamic>.from(w as Map))),
  );
}

class SiteWindow {
  final DateTime startUtc, endUtc;
  const SiteWindow(this.startUtc, this.endUtc);
  Map<String, String> toJson() => {'startUtc': startUtc.toIso8601String(),
    'endUtc': endUtc.toIso8601String()};
  factory SiteWindow.fromJson(Map<String, dynamic> json) => SiteWindow(
    DateTime.parse(json['startUtc'] as String),
    DateTime.parse(json['endUtc'] as String));
}

/// Explicit one-way messages. Site reports go to the organizer; plan messages
/// go to everybody and never contain the submitted locations.
class GroupMessage {
  static String site(String sessionId, ParticipantSite site) => jsonEncode({
    'kind': 'shapeify-site-v1', 'sessionId': sessionId, 'site': site.toJson(),
  });

  static ParticipantSite readSite(String source, String expectedSessionId) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['kind'] != 'shapeify-site-v1' ||
        json['sessionId'] != expectedSessionId) {
      throw const FormatException('Location report is for a different group');
    }
    return ParticipantSite.fromJson(
        Map<String, dynamic>.from(json['site'] as Map));
  }

  static String plan(String sessionId, SharedPlan plan) => jsonEncode({
    'kind': 'shapeify-plan-v1', 'sessionId': sessionId, 'plan': plan.toJson(),
  });

  static SharedPlan readPlan(String source, String expectedSessionId) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['kind'] != 'shapeify-plan-v1' ||
        json['sessionId'] != expectedSessionId) {
      throw const FormatException('Sky plan is for a different group');
    }
    return SharedPlan.fromJson(
        Map<String, dynamic>.from(json['plan'] as Map));
  }
}
