import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roundhound/ui/session_page.dart';

void main() {
  testWidgets('location paste stays usable with a keyboard in the narrow frame',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? imported;
    await tester.pumpWidget(Center(child: SizedBox(width: 270, height: 540,
      child: MaterialApp(home: Scaffold(body: Center(child: Builder(
        builder: (context) => TextButton(onPressed: () async {
          imported = await showDialog<String>(context: context,
              builder: (_) => const PasteTextDialog(
                title: 'Paste a participant location',
                hint: 'Location report'));
        }, child: const Text('Open')),
      )))),
    )));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Paste from clipboard'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 290);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '{"kind":"shapeify-site-v1"}');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(imported, '{"kind":"shapeify-site-v1"}');
  });
}
