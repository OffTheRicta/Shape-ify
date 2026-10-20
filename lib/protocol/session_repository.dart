import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'session.dart';

/// Multiple private local sessions; imports still require explicit user action.
class SessionRepository {
  // Demo releases used the original keys. A real release starts with a clean
  // local session and never migrates simulated plans or observations into it.
  static const _demo = bool.fromEnvironment('SHAPEIFY_DEMO');
  static String get _activeKey => _demo
      ? 'roundhound.activeSessionId' : 'shapeify.real.activeSessionId';
  static String get _indexKey => _demo
      ? 'roundhound.sessionIds' : 'shapeify.real.sessionIds';
  static String _key(String id) => _demo
      ? 'roundhound.session.$id' : 'shapeify.real.session.$id';

  static Future<ExperimentSession> active() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_activeKey);
    if (id != null) {
      final encoded = prefs.getString(_key(id));
      if (encoded != null) return ExperimentSession.decode(encoded);
    }
    // Only demo mode may read the old unqualified store. It can contain
    // automatically generated observations from previous test installations.
    final legacy = _demo ? prefs.getString('session') : null;
    final session = legacy == null
        ? ExperimentSession(const Uuid().v4(), 'Star angle experiment', [])
        : ExperimentSession.decode(legacy);
    await save(session);
    return session;
  }

  static Future<void> save(ExperimentSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = List<String>.from(prefs.getStringList(_indexKey) ?? <String>[]);
    if (!ids.contains(session.id)) ids.add(session.id);
    await prefs.setString(_key(session.id), session.encode());
    await prefs.setStringList(_indexKey, ids);
    await prefs.setString(_activeKey, session.id);
    if (_demo) await prefs.setString('session', session.encode());
  }

  static Future<List<ExperimentSession>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_indexKey) ?? <String>[];
    return [for (final id in ids)
      if (prefs.getString(_key(id)) case final encoded?)
        ExperimentSession.decode(encoded)];
  }

  static Future<ExperimentSession> join(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key(id));
    final session = existing == null
        ? ExperimentSession(id, 'Star angle experiment', [])
        : ExperimentSession.decode(existing);
    await save(session);
    return session;
  }

  static Future<ExperimentSession> create(String id, String title) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_key(id))) throw StateError('That session already exists');
    final session = ExperimentSession(id, title.trim().isEmpty
        ? 'Star angle experiment' : title.trim(), []);
    await save(session);
    return session;
  }
}
