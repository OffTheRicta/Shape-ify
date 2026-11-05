import 'package:flutter_test/flutter_test.dart';
import 'package:roundhound/measurement/observation.dart';
import 'package:roundhound/protocol/session.dart';
import 'package:roundhound/solver/comparison.dart';
import 'package:roundhound/solver/ray_geometry.dart';
import 'package:roundhound/reconstruction/layout.dart';
import 'package:roundhound/astronomy/visibility.dart';

Observation sight(String id,{double altitude=45,double azimuth=90,DateTime? time,String? observer,String star='Vega'}) => Observation(
  id:id,observer:observer??id,starId:star,method:'manual',notes:'clear',observedUtc:time??DateTime.utc(2026,9,23),
  latitude:-37.8,longitude:145,elevationM:20,instrumentHeightM:1.5,
  altitudeDeg:altitude,azimuthDeg:azimuth,angularUncertaintyDeg:1,positionUncertaintyM:10,nakedEyeConfirmed:true);
void main() {
  test('ray follows local east north up convention',(){
    final r=sight('a',altitude:0,azimuth:90).localRay;
    expect(r[0],closeTo(1,1e-12));expect(r[1],closeTo(0,1e-12));expect(r[2],closeTo(0,1e-12));
  });
  test('reported ray separation follows angular geometry', () {
    expect(localRaySeparationDeg(45, 0, 45, 0), closeTo(0, 1e-6));
    expect(localRaySeparationDeg(0, 0, 0, 90), closeTo(90, 1e-6));
  });
  test('comparison requires the same star and accepts later sightings',(){
    expect(ComparisonSolver.compare(sight('a'),sight('b',altitude:46))!.raySeparationDeg,closeTo(1,1e-7));
    final later = ComparisonSolver.compare(sight('a'),
      sight('b',time:DateTime.utc(2026,9,24,0,2)));
    expect(later, isNotNull);
    expect(later!.modelDependentResidualDifferenceDeg, isNotNull);
    expect(ComparisonSolver.compare(sight('a'),sight('b',star:'Sirius')),isNull);
  });
  test('roundtrip, merge and conflicting IDs',(){
    final s=ExperimentSession('session','test',[sight('a')]);
    expect(ExperimentSession.decode(s.encode()).observations.single.id,'a');
    expect(s.merge(s).observations.length,1);
    expect(()=>s.merge(ExperimentSession('session','test',[sight('a',altitude:50)])),throwsFormatException);
  });
  test('peer snapshots converge on every phone in either import order', () {
    final a = ExperimentSession('group', 'Night sky', [sight('a')]);
    final b = ExperimentSession('group', 'Night sky', [sight('b')]);
    final c = ExperimentSession('group', 'Night sky', [sight('c')]);
    final first = a.merge(b).merge(c).merge(b);
    final second = c.merge(a).merge(b).merge(a);
    expect(first.observations.map((o) => o.id).toSet(), {'a', 'b', 'c'});
    expect(second.observations.map((o) => o.id).toSet(), {'a', 'b', 'c'});
    expect(first.observations.map((o) => o.id).toList(),
        second.observations.map((o) => o.id).toList());
    expect(ComparisonSolver.all(first.observations).length, 3);
    expect(ComparisonSolver.all(second.observations).length, 3);
  });
  test('three star records at one station draw one station', () {
    final a = sight('a', observer: 'Station one');
    final b = sight('b', altitude: 46, observer: 'Station one');
    final c = sight('c', altitude: 47, observer: 'Station one');
    final stations = StationLayout.arrange([c, a, b]);
    expect(stations.length, 1);
    expect(stations.single.observations.map((o) => o.id).toList(),
        ['a', 'b', 'c']);
  });
  test('assembly waits for every planned site and all three shared stars', () {
    final records = [
      for (final station in ['Adelaide', 'Melbourne', 'Perth'])
        for (final star in ['Vega', 'Sirius', 'Canopus'])
          sight('$station-$star', observer: station, star: star),
    ];
    const stars = ['Vega', 'Sirius', 'Canopus'];
    expect(AssemblyLayout.ready(StationLayout.arrange(records.take(8)),
        stars, 3, const []), isFalse);
    expect(AssemblyLayout.ready(StationLayout.arrange(records),
        stars, 3, const []), isTrue);
    expect(AssemblyLayout.ready(StationLayout.arrange(records),
        stars, 2, const ['Perth']), isTrue);
    expect(AssemblyLayout.ready(StationLayout.arrange(records),
        stars, 3, const ['Perth']), isFalse);
    expect(AssemblyLayout.staging(0, 360).x,
        lessThan(AssemblyLayout.staging(1, 360).x));
    expect(AssemblyLayout.staging(1, 360).x,
        lessThan(AssemblyLayout.staging(2, 360).x));
  });
  test('rejects invalid input and unsupported schema',(){
    expect(sight('a',azimuth:360).validate(),isNotEmpty);
    expect(()=>ExperimentSession.decode('{"schemaVersion":2}'),throwsFormatException);
    expect(Visibility.eligible(sight('a',altitude:0)),isFalse);
  });
}
