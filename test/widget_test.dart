import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator, Opacity, ValueKey;
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
    // After the intro, group setup is the first visible screen. A location
    // request must not hold it behind a full-screen spinner.
    for (var frame = 0; frame < 20 &&
        find.text('Create group').evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Create group'), findsOneWidget);
    expect(find.text('Join group'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
