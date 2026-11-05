import 'package:flutter_test/flutter_test.dart';
import 'package:roundhound/astronomy/sky.dart';
import 'package:roundhound/protocol/group_plan.dart';
import 'package:roundhound/protocol/session.dart';

void main() {
  test('location message is rounded, addressed and separate from sky plan', () {
    final site = ParticipantSite.rounded(
        'Station A', -37.81234, 144.97654, DateTime.utc(2026, 9, 25));
    expect(site.latitude, -37.81);
    expect(site.longitude, 144.98);
    final message = GroupMessage.site('group', site);
    expect(GroupMessage.readSite(message, 'group').station, 'Station A');
    expect(() => GroupMessage.readSite(message, 'other'), throwsFormatException);

    final plan = SharedPlan(['Sirius', 'Rigel', 'Canopus'],
        DateTime.utc(2026, 9, 26), DateTime.utc(2026, 9, 25), 2);
    final outward = GroupMessage.plan('group', plan);
    expect(outward.contains('latitude'), isFalse);
    expect(GroupMessage.readPlan(outward, 'group').stars, plan.stars);
    expect(() => GroupMessage.readPlan(outward, 'other'), throwsFormatException);
  });

  test('new site invalidates prior plan and locations stay off peer exports', () {
    final a = ParticipantSite.rounded('A', -37.8, 145, DateTime.utc(2026, 9, 25));
    final b = ParticipantSite.rounded('B', -37.7, 145, DateTime.utc(2026, 9, 25));
    final planned = ExperimentSession('group', 'Night', [], sites: [a]).withPlan(
      SharedPlan(['Sirius', 'Rigel', 'Canopus'],
        DateTime.utc(2026, 9, 26), DateTime.utc(2026, 9, 25), 2));
    expect(planned.withSite(b).plan, isNull);
    final peerCopy = ExperimentSession.decode(planned.encode(includeSites: false));
    expect(peerCopy.sites, isEmpty);
    expect(peerCopy.plan!.stars, planned.plan!.stars);
  });

  test('shared window checks darkness and target altitude at every site', () {
    const nearby = [SkyLocation(-37.8, 145), SkyLocation(-37.9, 145.1)];
    final window = SkyGuide.chooseCommon(nearby, DateTime.utc(2026, 9, 25));
    expect(window, isNotNull);
    expect(window!.stars.length, 3);
    for (final site in nearby) {
      expect(SkyGuide.sunAltitude(site.latitude, site.longitude, window.utc),
          lessThan(-8));
      for (final star in window.stars) {
        final altitude = SkyGuide.horizontal(star, site.latitude,
            site.longitude, window.utc).altitudeDeg;
        expect(altitude, inInclusiveRange(18, 78));
      }
    }
    expect(SkyGuide.chooseCommon(const [SkyLocation(0, 0), SkyLocation(0, 180)],
        DateTime.utc(2026, 9, 25), lookaheadDays: 3), isNull);
    final subset = SkyGuide.chooseDarkSubset(const [
      SkyLocation(0, 0), SkyLocation(0, 180), SkyLocation(0, 1),
    ], DateTime.utc(2026, 9, 25), lookaheadDays: 3);
    expect(subset, isNotNull);
    expect(subset!.includedIndexes, [0, 2]);
    expect(subset.window.stars.length, 3);
  });

  test('already dark nearby stations receive a usable window right now', () {
    final now = DateTime.utc(2026, 9, 26, 17, 3); // 3:03 a.m. AEST.
    const sites = [SkyLocation(-33.8688, 151.2093),
      SkyLocation(-33.8690, 151.2090), SkyLocation(-33.8685, 151.2091)];
    expect(sites.every((s) => SkyGuide.sunAltitude(s.latitude,
      s.longitude, now) < -8), isTrue);
    final window = SkyGuide.chooseCommon(sites, now, lookaheadDays: 1);
    expect(window, isNotNull);
    expect(window!.utc.difference(now), const Duration(minutes: 5));
    expect(window.stars.length, 3);
  });

  test('excluded station is identified in shared plan without its location', () {
    final plan = SharedPlan(['Sirius', 'Rigel', 'Canopus'],
      DateTime.utc(2026, 9, 26), DateTime.utc(2026, 9, 25), 2,
      excludedStations: ['Station C']);
    final message = GroupMessage.plan('group', plan);
    expect(message, contains('Station C'));
    expect(message.contains('latitude'), isFalse);
    expect(GroupMessage.readPlan(message, 'group').excludedStations,
        ['Station C']);
  });

  test('distributed demo keeps daylight sites and gives each its own window', () {
    final now = DateTime.utc(2026, 9, 26, 17);
    const sites = [SkyLocation(-33.8, 151.2), SkyLocation(-33.9, 151.3),
      SkyLocation(-34, 151.1)];
    final chosen = SkyGuide.planAcrossSites(sites, now, demo: true);
    expect(chosen, isNotNull);
    expect(chosen!.stars.length, 3);
    expect(chosen.windows.length, sites.length);
    expect(chosen.windows.every((list) => list.isNotEmpty), isTrue);
    expect(chosen.reservedAt(now), isEmpty);
    for (var i = 0; i < sites.length; i++) {
      for (final star in chosen.stars) {
        final altitude = SkyGuide.horizontal(star, sites[i].latitude,
          sites[i].longitude, now).altitudeDeg;
        expect(altitude, inInclusiveRange(12, 85));
      }
    }
  });

  test('southern star preference chooses Acrux when all can see it', () {
    const sites = [SkyLocation(-35, 150), SkyLocation(-34, 151),
      SkyLocation(-36, 149)];
    final chosen = SkyGuide.planAcrossSites(sites,
      DateTime.utc(2026, 9, 29, 10), demo: false);
    expect(chosen, isNotNull);
    expect(chosen!.stars.map((s) => s.name), contains('Acrux'));
  });

  test('opening tier favours everyone within 30 minutes before 90% now', () {
    final choice = SkyGuide.chooseOpening(
      [9, 9, 9, 10, 9, 8, 8], [0, 5, 10, 15, 20, 25, 30], 10);
    expect(choice, isNotNull);
    expect(choice!.priority, 0);
    expect(choice.timeIndex, 3);
    expect(choice.included, 10);
  });

  test('opening tier descends from 90% to the 60% floor', () {
    const minutes = [0, 5, 10, 15, 20, 25, 30];
    final ninety = SkyGuide.chooseOpening([9, 10, 10, 11, 10, 8, 7],
      minutes, 12);
    expect(ninety!.priority, 10);
    expect(ninety.timeIndex, 3);
    final eighty = SkyGuide.chooseOpening([8, 10, 8, 9, 8, 7, 6],
      minutes, 12);
    expect(eighty!.priority, 20);
    expect(eighty.timeIndex, 1);
    final minimum = SkyGuide.chooseOpening([0, 1, 2, 8, 2, 2, 1],
      minutes, 12);
    expect(minimum!.included, 8);
    expect(minimum.priority, 40);
    expect(SkyGuide.chooseOpening([0, 1, 2, 7, 3, 3, 1],
      minutes, 12), isNull);
  });

  test('four people still need at least three at the opening', () {
    expect(SkyGuide.chooseOpening([2, 3], [0, 5], 4)!.timeIndex, 1);
    expect(SkyGuide.chooseOpening([2, 2], [0, 5], 4), isNull);
  });

  test('sixty percent of ten can go now; fifty percent cannot', () {
    final now = DateTime.utc(2026, 9, 29, 12);
    const dark = SkyLocation(-37.81, 144.96);
    const daylight = SkyLocation(-37.81, -35.04);
    final sixNow = SkyGuide.planAcrossSites([
      for (var i = 0; i < 6; i++) dark,
      for (var i = 0; i < 4; i++) daylight,
    ], now);
    expect(sixNow, isNotNull);
    expect(sixNow!.openingReady, isTrue);
    expect(sixNow.reservedAt(now).length, 4);
    expect(sixNow.windows.every((w) => w.isNotEmpty), isTrue);

    final fiveNow = SkyGuide.planAcrossSites([
      for (var i = 0; i < 5; i++) dark,
      for (var i = 0; i < 5; i++) daylight,
    ], now);
    expect(fiveNow, isNull);
  });

  test('a participant with no shared window is named before a plan is sent', () {
    final now = DateTime.utc(2026, 9, 29, 12);
    const sites = [SkyLocation(-37.81, 144.96),
      SkyLocation(-37.80, 144.97), SkyLocation(-37.82, 144.95),
      SkyLocation(89, 0)];
    expect(SkyGuide.planAcrossSites(sites, now), isNull);
    final proposal = SkyGuide.planAcrossSites(sites, now,
      allowBlocked: true);
    expect(proposal, isNotNull);
    expect(proposal!.windows.take(3).every((w) => w.isNotEmpty), isTrue);
    expect(proposal.windows.last, isEmpty);
    expect(SkyGuide.hasIndependentThreeSoon(sites.first, now), isTrue);
    expect(SkyGuide.hasIndependentThreeSoon(sites.last, now), isFalse);
  });

  test('tomorrow-only membership never creates a Go plan today', () {
    final now = DateTime.utc(2026, 9, 29); // Daytime in Melbourne.
    const sites = [SkyLocation(-37.81, 144.96),
      SkyLocation(-37.80, 144.97), SkyLocation(-37.82, 144.95)];
    expect(SkyGuide.planAcrossSites(sites, now), isNull);
    final proposal = SkyGuide.planAcrossSites(sites, now,
      allowBlocked: true);
    expect(proposal, isNotNull);
    expect(proposal!.openingReady, isFalse);
    expect(proposal.nextOpeningUtc, isNotNull);
    expect(proposal.nextOpeningUtc!.difference(now).inHours,
      inInclusiveRange(1, 12));
  });

  test('permanent sky mismatch differs from a temporary missed window', () {
    final now = DateTime.utc(2026, 6, 21, 12);
    const incompatible = [SkyLocation(-70, 0), SkyLocation(-70, 1),
      SkyLocation(-70, -1), SkyLocation(89, 0)];
    expect(SkyGuide.geometricallyCompatible(
      GroupSkyRequest(incompatible, now)), [true, true, true, false]);

    const temporary = [SkyLocation(-37.8, 145), SkyLocation(-37.8, 145),
      SkyLocation(-37.8, 145), SkyLocation(89, 0)];
    expect(SkyGuide.geometricallyCompatible(
      GroupSkyRequest(temporary, now)), [true, true, true, true]);
  });

  test('later opening belongs to today, not the 48-hour reserve period', () {
    const offsets = [0, 5, 10, 30, 35, 40, 715, 720, 725, 1440];
    expect(SkyGuide.chooseLaterToday(
      [0, 1, 2, 2, 3, 8, 9, 12, 12, 12], offsets, 8), 5);
    expect(SkyGuide.chooseLaterToday(
      [0, 1, 2, 2, 2, 2, 2, 8, 12, 12], offsets, 8), 7);
    expect(SkyGuide.chooseLaterToday(
      [0, 1, 2, 2, 2, 2, 2, 2, 12, 12], offsets, 8), isNull);
  });

  test('only catalogue stars no dimmer than the naked-eye limit are used', () {
    expect(SkyGuide.brightStars, isNotEmpty);
    expect(SkyGuide.brightStars.every((s) =>
      s.magnitude <= SkyGuide.maxCatalogMagnitude), isTrue);
    expect(SkyGuide.brightStars.map((s) => s.name).toSet().length,
      SkyGuide.brightStars.length);
    expect(SkyGuide.brightStars.map((s) => s.name), contains('Ankaa'));
  });

  test('the three guide stars also constrain an independent ground angle', () {
    GuideStar star(String name) => SkyGuide.brightStars.firstWhere(
      (candidate) => candidate.name == name);
    expect(SkyGuide.independentTrio(star('Acrux'), star('Mimosa'),
      star('Hadar')), isFalse);
    expect(SkyGuide.independentTrio(star('Canopus'), star('Achernar'),
      star('Acrux')), isTrue);
  });

  test('live Melbourne stations are not reserved when their shared stars are up', () {
    final now = DateTime.utc(2026, 9, 29, 12, 43); // 10:43 p.m. AEST.
    const sites = [SkyLocation(-37.81, 144.96),
      SkyLocation(-37.80, 144.97), SkyLocation(-37.82, 144.95)];
    final plan = SkyGuide.planAcrossSites(sites, now);
    expect(plan, isNotNull);
    expect(plan!.reservedAt(now), isEmpty);
    expect(plan.stars.map((star) => star.name), contains('Acrux'));
    for (var i = 0; i < sites.length; i++) {
      expect(plan.windows[i].first.startUtc, now);
      expect(SkyGuide.sunAltitude(sites[i].latitude,
          sites[i].longitude, now), lessThan(-8));
      for (final star in plan.stars) {
        expect(SkyGuide.horizontal(star, sites[i].latitude,
            sites[i].longitude, now).altitudeDeg,
            inInclusiveRange(12, 85));
      }
    }
  });

  test('dark stations observe now even if Acrux is temporarily too low', () {
    final now = DateTime.utc(2026, 9, 29, 14); // Midnight in Melbourne.
    const sites = [SkyLocation(-37.81, 144.96),
      SkyLocation(-37.80, 144.97), SkyLocation(-37.82, 144.95)];
    expect(sites.every((s) => SkyGuide.sunAltitude(s.latitude,
      s.longitude, now) < -8), isTrue);
    final acrux = SkyGuide.brightStars.firstWhere((s) => s.name == 'Acrux');
    expect(SkyGuide.horizontal(acrux, sites.first.latitude,
      sites.first.longitude, now).altitudeDeg, lessThan(12));
    final plan = SkyGuide.planAcrossSites(sites, now);
    expect(plan, isNotNull);
    expect(plan!.reservedAt(now), isEmpty);
    expect(plan.stars.map((s) => s.name), isNot(contains('Acrux')));
    for (var i = 0; i < sites.length; i++) {
      expect(plan.windows[i].first.startUtc, now);
      for (final star in plan.stars) {
        expect(SkyGuide.horizontal(star, sites[i].latitude,
          sites[i].longitude, now).altitudeDeg, inInclusiveRange(12, 85));
      }
    }
  });

  test('dark observers start while a distant daylight member waits', () {
    final now = DateTime.utc(2026, 9, 29, 12);
    const sites = [SkyLocation(-37.81, 144.96),
      SkyLocation(-37.80, 144.97), SkyLocation(-37.82, 144.95),
      SkyLocation(-37.81, -35.04)];
    expect(SkyGuide.sunAltitude(sites.first.latitude,
      sites.first.longitude, now), lessThan(-8));
    expect(SkyGuide.sunAltitude(sites.last.latitude,
      sites.last.longitude, now), greaterThan(-8));
    final plan = SkyGuide.planAcrossSites(sites, now);
    expect(plan, isNotNull);
    expect(plan!.reservedAt(now), [3]);
    for (var i = 0; i < 3; i++) {
      expect(plan.windows[i].first.startUtc, now);
    }
    expect(plan.windows.last.first.startUtc.isAfter(now), isTrue);
    expect(plan.windows.last.first.endUtc.difference(now).inHours,
      lessThan(48));
  });
}
