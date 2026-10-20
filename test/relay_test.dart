import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roundhound/protocol/relay_client.dart';
import 'package:roundhound/protocol/group_plan.dart';
import 'package:roundhound/protocol/session_repository.dart';
import 'package:roundhound/measurement/observation.dart';

void main() {
  test('location is quantized on the phone before upload', () {
    final location = CoarseLocation.from(-33.8688, 151.2093);
    expect((location['latitude']! + 33.8688).abs(), lessThan(0.02));
    expect((location['longitude']! - 151.2093).abs(), lessThan(0.03));
    expect(CoarseLocation.from(0.001, 0.001), {
      'latitude': 0.0, 'longitude': 0.0});
  });

  test('development HTTP is limited to private-network hosts', () {
    expect(RelayClient.checkUrl('http://192.168.1.20:8765/'),
      'http://192.168.1.20:8765');
    expect(() => RelayClient.checkUrl('http://example.org'),
      throwsFormatException);
    expect(RelayClient.checkUrl('https://example.org'),
      'https://example.org');
  });

  test('corrected group location clears an unused local star plan', () async {
    SharedPreferences.setMockInitialValues({});
    const member = RelayIdentity('http://192.168.0.100:8765',
      'ABCDE', 'member-id', 'Owl', 'test-token', false);
    final session = await SessionRepository.join(member.code);
    await SessionRepository.save(session.withPlan(SharedPlan(
      ['Sirius', 'Rigel', 'Canopus'], DateTime.utc(2026, 9, 27, 12),
      DateTime.utc(2026, 9, 26, 12), 3)));
    final updated = await RelaySync.apply(member,
      {'phase': 'planning', 'plan': null, 'published': null});
    expect(updated.plan, isNull);
    expect((await SessionRepository.active()).plan, isNull);
  });

  test('real group never submits an automatic or unconfirmed sighting', () {
    const real = RelayIdentity('https://relay.roundhound.info', 'ABCDE',
      'id', 'Owl', 'token', true);
    const demo = RelayIdentity('https://relay.roundhound.info', 'ABCDE',
      'id', 'Owl', 'token', true, demo: true);
    Observation sight({required bool simulated, required bool confirmed}) =>
      Observation(id: 'id', observer: 'Owl', starId: 'Sirius', method: 'camera',
        notes: '', observedUtc: DateTime.utc(2026), latitude: -37,
        longitude: 145, elevationM: 0, instrumentHeightM: 1.5,
        altitudeDeg: 30, azimuthDeg: 100, angularUncertaintyDeg: 5,
        positionUncertaintyM: 2000, simulated: simulated,
        nakedEyeConfirmed: confirmed);
    expect(RelaySync.canSubmit(real, sight(simulated: true, confirmed: false)), isFalse);
    expect(RelaySync.canSubmit(real, sight(simulated: false, confirmed: false)), isFalse);
    expect(RelaySync.canSubmit(real, sight(simulated: false, confirmed: true)), isTrue);
    expect(RelaySync.canSubmit(demo, sight(simulated: true, confirmed: false)), isTrue);
  });
}
