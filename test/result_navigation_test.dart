import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roundhound/measurement/observation.dart';
import 'package:roundhound/reconstruction/layout.dart';
import 'package:roundhound/ui/result_plots.dart';
import 'package:roundhound/ui/scroll_cues.dart';

Observation _sight(String id) => Observation(
  id: id, observer: id, starId: 'Vega', method: 'SIMULATED', notes: '',
  observedUtc: DateTime.utc(2026, 9, 27), latitude: -37.8, longitude: 145,
  elevationM: 20, instrumentHeightM: 1.5, altitudeDeg: 45,
  azimuthDeg: 90, angularUncertaintyDeg: 1, positionUncertaintyM: 10,
  nakedEyeConfirmed: false, simulated: true,
);

void main() {
  testWidgets('plot action stays beneath the controls in either view', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ResultPlots(stations: StationLayout.arrange([_sight('A')]),
        onCheckAgain: () {})))));
    final continueButton = find.text('Continue to globe plot');
    expect(tester.getTopLeft(continueButton).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('result-viewport'))).dy));
    expect(find.textContaining('DEMO'), findsNothing);
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pump();
    final backButton = find.text('Back to flat plot');
    expect(backButton, findsOneWidget);
    expect(find.textContaining('Drag to move'), findsOneWidget);
  });

  testWidgets('title, plot, controls, actions, then explanation', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ResultPlots(stations: StationLayout.arrange([_sight('A')]),
        sessionId: 'QYMSL', onWebView: (_) {}, onCheckAgain: () {},
        description: 'Short explanation at the bottom.')))));
    final plot = find.byKey(const Key('result-viewport'));
    final title = find.text('Every phone builds the same picture');
    final zoom = find.byKey(const Key('zoom-slider'));
    final web = find.byKey(const Key('view-results-via-web'));
    final explanation = find.text('Short explanation at the bottom.');
    expect(tester.getTopLeft(title).dy, lessThan(tester.getTopLeft(plot).dy));
    expect(tester.getTopLeft(plot).dy, lessThan(tester.getTopLeft(zoom).dy));
    expect(tester.getTopLeft(zoom).dy, lessThan(tester.getTopLeft(web).dy));
    expect(tester.getTopLeft(web).dy,
      lessThan(tester.getTopLeft(explanation).dy));
    expect(find.text('Gold: selected  ·  Green: stations'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue to globe plot'));
    await tester.tap(find.text('Continue to globe plot'));
    await tester.pump();
    expect(find.text('Gold: selected  ·  Green: stations  ·  Faded: far side'),
      findsOneWidget);
  });

  testWidgets('web action reports the currently visible candidate', (tester) async {
    final requested = <bool>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ResultPlots(stations: StationLayout.arrange([_sight('A')]),
        sessionId: 'QYMSL', onWebView: requested.add,
        onCheckAgain: () {})))));
    final web = find.byKey(const Key('view-results-via-web'));
    await tester.ensureVisible(web);
    await tester.pumpAndSettle();
    await tester.tap(web);
    expect(requested, [false]);
    final next = find.text('Continue to globe plot');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pump();
    await tester.ensureVisible(web);
    await tester.pumpAndSettle();
    await tester.tap(web);
    expect(requested, [false, true]);
  });

  testWidgets('group website link is visible while results are still arriving', (tester) async {
    final requested = <bool>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ResultPlots(
      stations: const [], sessionId: 'QYMSL', onWebView: requested.add,
      onCheckAgain: () {}))));
    expect(find.text('View results on website'), findsOneWidget);
    await tester.tap(find.byKey(const Key('view-results-via-web')));
    expect(requested, [false]);
  });

  test('station bounds initially fill about 80 percent of the tighter axis', () {
    const viewport = Size(320, 340);
    final wide = ResultViewportFit.calculate(
      [const Offset(130, 150), const Offset(150, 150)], viewport);
    expect(wide.zoom, closeTo(11, .001));
    expect(20 * wide.zoom + 36, closeTo(viewport.width * .8, .001));

    final tall = ResultViewportFit.calculate(
      [const Offset(150, 120), const Offset(150, 160)], viewport);
    expect(40 * tall.zoom + 36, closeTo(viewport.height * .8, .001));

    final coincident = ResultViewportFit.calculate(
      [const Offset(120, 150), const Offset(120, 150)], viewport);
    expect(coincident.zoom, 1);
    expect(coincident.pan, const Offset(40, 20));
  });

  testWidgets('two fingers enlarge a result, double tap resets zoom', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ResultPlots(stations: StationLayout.arrange([_sight('A'), _sight('B')]),
        onCheckAgain: () {})))));
    expect(find.textContaining('1.0×'), findsOneWidget);
    final plot = find.byKey(const Key('result-viewport'));
    final centre = tester.getCenter(plot);
    final left = await tester.startGesture(centre + const Offset(-25, 0), pointer: 1);
    final right = await tester.startGesture(centre + const Offset(25, 0), pointer: 2);
    await tester.pump();
    await left.moveBy(const Offset(-45, 0));
    await right.moveBy(const Offset(45, 0));
    await tester.pump();
    expect(find.textContaining('1.0×'), findsNothing);
    await left.up();
    await right.up();
    await tester.pump();
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(centre);
    await tester.pump();
    expect(find.textContaining('1.0×'), findsOneWidget);
    // Let the double-tap recognizer release its short tracking timer.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('compact zoom slider works on both candidate plots', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ResultPlots(stations: StationLayout.arrange([_sight('A')]),
        onCheckAgain: () {})))));
    final zoomSlider = find.byKey(const Key('zoom-slider'));
    expect(zoomSlider, findsOneWidget);
    expect(tester.getSize(zoomSlider).height, lessThanOrEqualTo(38));
    tester.widget<Slider>(zoomSlider).onChanged!(.5);
    await tester.pump();
    expect(find.text('64.0×'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue to globe plot'));
    await tester.tap(find.text('Continue to globe plot'));
    await tester.pump();
    await tester.pump();
    expect(zoomSlider, findsOneWidget);
    tester.widget<Slider>(zoomSlider).onChanged!(.25);
    await tester.pump();
    expect(find.text('4.0×'), findsOneWidget);
  });

  testWidgets('step change replaces top action and status updates keep scroll', (tester) async {
    String action = 'begin';
    final actionState = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ValueListenableBuilder<int>(valueListenable: actionState,
        builder: (context, _, child) => ActionFirstScroll(actionId: action,
          builder: (controller) => ListView(controller: controller,
            children: [
              FilledButton(onPressed: () {}, child: Text(action)),
              for (var i = 0; i < 20; i++)
                SizedBox(height: 85, child: Text('Station $i')),
            ])),
      ))));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final offset = list.controller!.offset;
    expect(offset, greaterThan(0));
    actionState.value++; // Polling brought in new status, but the step is the same.
    await tester.pump();
    expect(list.controller!.offset, offset);
    action = 'send plan';
    actionState.value++;
    await tester.pump();
    await tester.pump();
    expect(list.controller!.offset, 0);
    expect(find.text('send plan'), findsOneWidget);
  });

}
