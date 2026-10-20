import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show Opacity, ValueKey;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roundhound/main.dart';

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
    // Step beyond the exact animation endpoint, then allow the navigator and
    // location initialization to build on the following frame.
    for (var frame = 0; frame < 10 &&
        find.text('Shape-ify').evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Location is provided by Android/iOS, not by the widget test runner.
    // A loading indicator may animate indefinitely until that result arrives.
    expect(find.text('Shape-ify'), findsOneWidget);
    expect(find.byTooltip('Results & sharing'), findsOneWidget);
  });
}
