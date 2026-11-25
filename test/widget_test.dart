import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, MaterialApp, Opacity, Size, SizedBox, ValueKey;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roundhound/main.dart';
import 'package:roundhound/ui/guided_home.dart';

void main() {
  testWidgets('crest zoom and logo crossfade hand off to app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RoundhoundApp());
    expect(find.text('Shape-ify'), findsNothing);
    double opacity(String key) => tester.widget<Opacity>(
        find.byKey(ValueKey(key))).opacity;
    expect(opacity('intro-crest'), closeTo(0, 1e-12));
    expect(opacity('intro-logo'), closeTo(0, 1e-12));
    await tester.pump(const Duration(seconds: 3));
    expect(opacity('intro-crest'), closeTo(1, 1e-12));
    await tester.pump(const Duration(seconds: 1));
    expect(opacity('intro-crest'), closeTo(1, 1e-12));
    await tester.pump(const Duration(milliseconds: 1700));
    expect(opacity('intro-crest'), closeTo(0.15, 0.01));
    expect(opacity('intro-logo'), closeTo(0, 1e-12));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity('intro-crest'), closeTo(0, 1e-12));
    expect(opacity('intro-logo'), closeTo(0.15, 0.01));
    await tester.pump(const Duration(milliseconds: 1700));
    expect(opacity('intro-logo'), closeTo(1, 1e-12));
    await tester.pump(const Duration(seconds: 2));
    expect(opacity('intro-logo'), closeTo(1, 1e-12));
    await tester.pump(const Duration(seconds: 1));
    // A fresh install can choose a role before any location request.
    for (var frame = 0; frame < 20 &&
        find.text('Create Group').evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Measure • Construct • Conclude'), findsOneWidget);
    expect(find.text('Create Group'), findsOneWidget);
    expect(find.text('Join Group'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Home opens separate create and join forms on a small phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: GuidedHome()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Group'));
    await tester.pumpAndSettle();
    expect(find.text('Create group'), findsOneWidget);
    expect(find.text('Five-letter group code'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join Group'));
    await tester.pumpAndSettle();
    expect(find.text('Create group'), findsNothing);
    expect(find.text('Five-letter group code'), findsOneWidget);
    expect(find.text('Join group'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
