import 'package:beta_app/maps/voice_guidance_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('voice toggle exposes enabled state and lets user disable and re-enable it', (tester) async {
    var enabled = true;
    Future<void> pump() async => tester.pumpWidget(MaterialApp(home: Scaffold(body:
      VoiceGuidanceToggle(enabled: enabled, onChanged: (value) { enabled = value; }))));
    await pump();
    expect(find.text('Indicaciones por voz'), findsOneWidget);
    expect(find.bySemanticsLabel('Indicaciones por voz'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    expect(enabled, isFalse);
    await pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    expect(enabled, isTrue);
  });
}
