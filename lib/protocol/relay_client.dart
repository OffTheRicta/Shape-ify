import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../measurement/observation.dart';
import 'group_plan.dart';
import 'session.dart';
import 'session_repository.dart';

class RelayIdentity {
  final String url, code, memberId, tag, token;
  final bool master;
  final bool demo;
  const RelayIdentity(this.url, this.code, this.memberId, this.tag,
      this.token, this.master, {this.demo = false});
  Map<String, dynamic> toJson() => {'url': url, 'code': code,
    'memberId': memberId, 'tag': tag, 'token': token, 'master': master,
    'demo': demo};
  factory RelayIdentity.fromJson(Map<String, dynamic> value) => RelayIdentity(
    value['url'] as String, value['code'] as String,
    value['memberId'] as String, value['tag'] as String,
    value['token'] as String, value['master'] as bool,
    demo: value['demo'] == true);
}

class RelayStore {
  static const _key = 'shapeify.relay.identity';
  static Future<RelayIdentity?> read() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    if (value == null) return null;
    final saved = RelayIdentity.fromJson(
      Map<String, dynamic>.from(jsonDecode(value) as Map));
    return saved.demo == const bool.fromEnvironment('SHAPEIFY_DEMO')
      ? saved : null;
  }
  static Future<void> save(RelayIdentity value) async {
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(value.toJson()));
  }
  static Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}

/// Quantize on the phone so the relay never receives the raw GPS fix.
class CoarseLocation {
  static Map<String, double> from(double latitude, double longitude) {
    final latStep = 2 / 111.32;
    final lat = ((latitude / latStep).round() * latStep).clamp(-90.0, 90.0).toDouble();
    final cosine = math.max(0.01, math.cos(lat * math.pi / 180));
    final lonStep = math.min(360.0, 2 / (111.32 * cosine));
    final lon = ((longitude / lonStep).round() * lonStep).clamp(-180.0, 180.0).toDouble();
    return {'latitude': double.parse(lat.toStringAsFixed(7)),
      'longitude': double.parse(lon.toStringAsFixed(7))};
  }
}

class RelayClient {
  final String url;
  final String? token;
  RelayClient(this.url, [this.token]);
  static String checkUrl(String source) {
    final uri = Uri.tryParse(source.trim());
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery ||
        uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/') ||
        !['http', 'https'].contains(uri.scheme)) {
      throw const FormatException('Enter a relay URL such as https://relay.example.org');
    }
    if (uri.scheme == 'http' && !['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host) &&
        !RegExp(r'^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(uri.host)) {
      throw const FormatException('Use HTTPS outside a local network');
    }
    return uri.toString().replaceFirst(RegExp(r'/$'), '');
  }
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.openUrl(method, Uri.parse('$url$path'));
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        // cPanel's PHP/FastCGI path can receive an empty php://input from a
        // chunked upload. Dart defaults to unknown length unless specified.
        final bytes = utf8.encode(jsonEncode(body));
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final response = await req.close().timeout(const Duration(seconds: 20));
      final payload = jsonDecode(await utf8.decoder.bind(response).join()) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('${payload['error'] ?? 'Relay error'} '
          '(HTTP ${response.statusCode}, $path)');
      }
      return payload;
    } finally { client.close(force: true); }
  }
  static Future<RelayIdentity> enter(String url, String tag, {String? code}) async {
    final normalized = checkUrl(url);
    final reply = await RelayClient(normalized).request('POST',
      code == null ? '/v1/groups' : '/v1/groups/${code.toUpperCase()}/join',
      {'tag': tag, 'demo': const bool.fromEnvironment('SHAPEIFY_DEMO')});
    final identity = RelayIdentity(normalized, reply['code'] as String,
      (reply['self'] as Map)['id'] as String, (reply['self'] as Map)['tag'] as String,
      reply['token'] as String, reply['isMaster'] as bool,
      demo: const bool.fromEnvironment('SHAPEIFY_DEMO'));
    await RelayStore.save(identity);
    await SessionRepository.join(identity.code);
    return identity;
  }
  static RelayClient forIdentity(RelayIdentity identity) =>
      RelayClient(identity.url, identity.token);
  String groupPath(RelayIdentity identity) => '/v1/groups/${identity.code}';
  Future<Map<String, dynamic>> status(RelayIdentity identity) =>
      request('GET', groupPath(identity));
  Future<Map<String, dynamic>> action(RelayIdentity identity, String action,
      [Map<String, dynamic>? data]) => request('POST',
      '${groupPath(identity)}/$action', data ?? {});
  Future<Map<String, dynamic>> site(RelayIdentity identity, double lat, double lon) =>
      action(identity, 'site', CoarseLocation.from(lat, lon));
  Future<Map<String, dynamic>> remove(RelayIdentity identity, String id,
      {String reason = 'manual'}) => request('DELETE',
        '${groupPath(identity)}/members/$id', {'reason': reason});
  Future<Map<String, dynamic>> submit(RelayIdentity identity, Observation o) =>
      action(identity, 'observations', {
        'id': o.id, 'starId': o.starId,
        'observedUtc': o.observedUtc.toIso8601String(),
        'method': o.method, 'notes': o.notes,
        'altitudeDeg': o.altitudeDeg, 'azimuthDeg': o.azimuthDeg,
        'angularUncertaintyDeg': o.angularUncertaintyDeg,
        'positionUncertaintyM': o.positionUncertaintyM,
        'nakedEyeConfirmed': o.nakedEyeConfirmed,
        'simulated': o.simulated,
        'azimuthReference': o.azimuthReference,
      });
}

/// Reconcile the relay into this phone's local session, where all solvers run.
class RelaySync {
  /// Real groups only transmit observations confirmed by a person in the app.
  static bool canSubmit(RelayIdentity identity, Observation observation) =>
      identity.demo || (!observation.simulated && observation.nakedEyeConfirmed);

  static Future<ExperimentSession> apply(RelayIdentity identity,
      Map<String, dynamic> state) async {
    var local = await SessionRepository.join(identity.code);
    final plan = state['plan'];
    if (plan is Map) {
      local = local.withPlan(SharedPlan.fromJson(Map<String, dynamic>.from(plan)));
    } else if (state['phase'] == 'planning' || state['phase'] == 'lobby') {
      local = ExperimentSession(identity.code, local.title,
        local.observations, sites: local.sites);
    }
    final published = state['published'];
    if (published is Map) {
      final remote = ExperimentSession.decode(jsonEncode(published));
      local = ExperimentSession(identity.code, local.title,
        [...remote.observations, ...local.observations.where((o) =>
          o.observer == identity.tag &&
          !remote.observations.any((r) => r.id == o.id))], plan: local.plan);
    }
    await SessionRepository.save(local);
    return local;
  }
  static Future<void> pushPending(RelayIdentity identity,
      Map<String, dynamic> state, ExperimentSession local) async {
    if (state['phase'] != 'observing') return;
    final members = state['members'] as List;
    final self = members.cast<Map>().firstWhere((m) => m['id'] == identity.memberId);
    if (self['excluded'] == true) return;
    final received = (self['received'] as List).cast<String>().toSet();
    final client = RelayClient.forIdentity(identity);
    for (final o in local.observations.where((o) => o.observer == identity.tag &&
        !received.contains(o.starId) && canSubmit(identity, o))) {
      await client.submit(identity, o);
    }
  }
}
