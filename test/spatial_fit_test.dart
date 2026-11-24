import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roundhound/astronomy/sky.dart';
import 'package:roundhound/measurement/observation.dart';
import 'package:roundhound/reconstruction/layout.dart';
import 'package:roundhound/reconstruction/spatial_fit.dart';
import 'package:roundhound/ui/result_plots.dart';

List<Observation> readings(
  String station,
  double latitude,
  double longitude, {
  bool magnetic = false,
}) {
  final time = DateTime.utc(2026, 11, 25);
  return [
    for (final (i, star) in [
      SkyGuide.brightStars[0],
      SkyGuide.brightStars[2],
      SkyGuide.brightStars[3],
    ].indexed)
      () {
        final utc = time.add(Duration(minutes: i * 18));
        final target = SkyGuide.horizontal(star, latitude, longitude, utc);
        return Observation(
          id: '$station$i',
          observer: station,
          starId: star.name,
          method: 'Synthetic catalogue fixture',
          notes: '',
          observedUtc: utc,
          latitude: latitude,
          longitude: longitude,
          elevationM: 0,
          instrumentHeightM: 0,
          altitudeDeg: target.altitudeDeg,
          azimuthDeg: SkyGuide.wrap(target.azimuthDeg - (magnetic ? 24 : 0)),
          angularUncertaintyDeg: .1,
          positionUncertaintyM: 5,
          nakedEyeConfirmed: false,
          simulated: true,
          azimuthReference: magnetic ? 'magnetic' : 'true',
        );
      }(),
  ];
}

void main() {
  test('timestamped magnetic rays recover the local up direction', () {
    final fit = StationOrientation.fit(
      readings('A', -33, 151, magnetic: true),
    )!;
    final latitude = -33 * math.pi / 180;
    final longitude = 151 * math.pi / 180;
    final expected = SpatialVector(
      math.cos(latitude) * math.cos(longitude),
      math.cos(latitude) * math.sin(longitude),
      math.sin(latitude),
    );
    expect(fit.magnetic, isTrue);
    expect((fit.up - expected).length, lessThan(1e-8));
    expect(fit.residualsDeg, everyElement(lessThan(1e-5)));
  });

  test('fits relative 3D positions with mutually consistent GPS baselines', () {
    final fit = SpatialFit.solve(
      StationLayout.arrange([
        ...readings('A', 0, 0),
        ...readings('B', 0, 90, magnetic: true),
        ...readings('C', 45, 40),
      ]),
    );
    final centres = fit.centresM!;
    expect(fit.baselineRmsM, lessThan(1e-5));
    expect(
      (centres[1] - centres[0]).length,
      closeTo(6378137 * math.sqrt2, 1e-5),
    );
    expect((centres[0] + centres[1] + centres[2]).length, lessThan(1e-8));
  });

  test('withholds a layout when the GPS baseline is unresolved', () {
    final fit = SpatialFit.solve(
      StationLayout.arrange([
        ...readings('A', 0, 0),
        ...readings('B', 0, .000001),
      ]),
    );
    expect(fit.centresM, isNull);
    expect(fit.unavailableReason, contains('GPS uncertainty'));
  });

  test('rejects repeated catalogue targets', () {
    final reading = readings('A', 0, 0).first;
    expect(StationOrientation.fit([reading, reading, reading]), isNull);
  });

  testWidgets('Results shows the fitted workspace for a complete session', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResultPlots(
              stations: StationLayout.arrange([
                ...readings('A', 0, 0),
                ...readings('B', 0, 90, magnetic: true),
              ]),
              onCheckAgain: () {},
            ),
          ),
        ),
      ),
    );
    final workspace = find.text('Continue to 3D workspace');
    await tester.ensureVisible(workspace);
    await tester.tap(workspace);
    await tester.pumpAndSettle();
    expect(find.textContaining('3D station fit'), findsOneWidget);
    expect(find.textContaining('Baseline RMS disagreement'), findsOneWidget);
    expect(find.text('1 fitted pair'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
