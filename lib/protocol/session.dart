import 'dart:convert';
import '../measurement/observation.dart';
import 'group_plan.dart';

class ExperimentSession {
  final String id, title;
  final List<Observation> observations;
  final List<ParticipantSite> sites;
  final SharedPlan? plan;
  ExperimentSession(this.id, this.title, Iterable<Observation> records,
      {Iterable<ParticipantSite> sites = const [], this.plan})
      : observations = List.unmodifiable(records),
        sites = List.unmodifiable(sites);

  Map<String, dynamic> toJson() => {'schemaVersion': 1, 'sessionId': id,
    'title': title, 'observations': observations.map((o) => o.toJson()).toList(),
    'sites': sites.map((site) => site.toJson()).toList(),
    if (plan != null) 'plan': plan!.toJson()};
  String encode({bool includeSites = true}) {
    final payload = toJson();
    if (!includeSites) payload.remove('sites');
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  ExperimentSession withSite(ParticipantSite site) => ExperimentSession(
    id, title, observations,
    sites: [...sites.where((old) => old.station != site.station), site],
    plan: null, // A location change requires a new group-wide sky check.
  );

  ExperimentSession withPlan(SharedPlan value) => ExperimentSession(
    id, title, observations, sites: sites, plan: value);

  ExperimentSession withObservation(Observation value) => ExperimentSession(
    id, title, [...observations, value], sites: sites, plan: plan);

  factory ExperimentSession.decode(String source) {
    final j = jsonDecode(source);
    if (j is! Map<String, dynamic> || j['schemaVersion'] != 1 ||
        j['sessionId'] is! String || (j['sessionId'] as String).isEmpty ||
        j['title'] is! String || j['observations'] is! List) {
      throw const FormatException('Unsupported or malformed session');
    }
    final records = (j['observations'] as List).map((e) => Observation.fromJson(Map<String,dynamic>.from(e as Map))).toList();
    final seen = <String, String>{};
    for (final o in records) {
      final value = jsonEncode(o.toJson());
      if (seen.containsKey(o.id) && seen[o.id] != value) throw FormatException('Conflicting observation ID: ${o.id}');
      seen[o.id] = value;
    }
    final ordered = [for (final id in seen.keys)
      records.firstWhere((o) => o.id == id)]
      ..sort((a, b) {
        final time = a.observedUtc.compareTo(b.observedUtc);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    final sites = <String, ParticipantSite>{};
    for (final entry in (j['sites'] as List? ?? const [])) {
      final site = ParticipantSite.fromJson(Map<String, dynamic>.from(entry as Map));
      if (sites.containsKey(site.station)) {
        throw const FormatException('Duplicate station in group location data');
      }
      sites[site.station] = site;
    }
    return ExperimentSession(j['sessionId'] as String, j['title'] as String,
      ordered, sites: sites.values,
      plan: j['plan'] == null ? null : SharedPlan.fromJson(
          Map<String, dynamic>.from(j['plan'] as Map)));
  }

  ExperimentSession merge(ExperimentSession other) {
    if (id != other.id) throw const FormatException('Different session IDs');
    final combined = <String, ParticipantSite>{
      for (final site in sites) site.station: site,
    };
    for (final site in other.sites) {
      final old = combined[site.station];
      if (old == null || site.reportedUtc.isAfter(old.reportedUtc)) {
        combined[site.station] = site;
      } else if (site.reportedUtc == old.reportedUtc &&
          (site.latitude != old.latitude || site.longitude != old.longitude)) {
        throw const FormatException('Conflicting station location');
      }
    }
    SharedPlan? chosen = plan;
    if (other.plan != null) {
      if (chosen == null || other.plan!.createdUtc.isAfter(chosen.createdUtc)) {
        chosen = other.plan;
      } else if (other.plan!.createdUtc == chosen.createdUtc &&
          jsonEncode(other.plan!.toJson()) != jsonEncode(chosen.toJson())) {
        throw const FormatException('Conflicting sky plans');
      }
    }
    return ExperimentSession.decode(ExperimentSession(id, title,
      [...observations, ...other.observations],
      sites: combined.values, plan: chosen).encode());
  }
}
