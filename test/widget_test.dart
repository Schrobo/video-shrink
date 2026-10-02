import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_shrink/app.dart';

void main() {
  testWidgets('file selection and settings remain usable in a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const VideoShrinkApp());
    expect(find.text('Datei auswählen'), findsOneWidget);
    expect(find.text('Video hier ablegen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Kleine Schrift besser erhalten'), findsNothing);
    expect(find.text('WhatsApp · bis 15 MB'), findsNothing);
    await tester.tap(find.text('Optionen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Kleine Schrift besser erhalten'));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
