import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roundhound/protocol/invite.dart';
import 'package:roundhound/protocol/session_repository.dart';
import 'package:roundhound/protocol/session.dart';

void main() {
  test('invite ID survives readable formatting and rejects incomplete codes', () {
    final code = InviteCode.create();
    expect(InviteCode.parse(code), code);
    expect(InviteCode.parse(code.toLowerCase().replaceAll('-', ' ')), code);
    expect(InviteCode.parse('RH-1234'), isNull);
  });


  test('joining another session preserves existing local data', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await SessionRepository.active();
    final master = await SessionRepository.create(InviteCode.create(), 'Master');
    expect((await SessionRepository.active()).id, master.id);
    await SessionRepository.join(first.id);
    expect((await SessionRepository.active()).id, first.id);
    expect((await SessionRepository.all()).map((s) => s.id).toSet(),
        containsAll([first.id, master.id]));
  });

  test('real release does not migrate the old demo session or plan', () async {
    final old = ExperimentSession('DEMOX', 'Old simulation', []);
    SharedPreferences.setMockInitialValues({
      'roundhound.activeSessionId': old.id,
      'roundhound.sessionIds': <String>[old.id],
      'roundhound.session.${old.id}': old.encode(),
      'session': old.encode(),
    });
    final fresh = await SessionRepository.active();
    expect(fresh.id, isNot(old.id));
    expect(fresh.observations, isEmpty);
    expect((await SessionRepository.all()).map((s) => s.id), isNot(contains(old.id)));
    expect((await SessionRepository.join(old.id)).observations, isEmpty);
  });
}
