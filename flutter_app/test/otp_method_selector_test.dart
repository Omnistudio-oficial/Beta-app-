import 'package:beta_app/widgets/otp_method_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows all three OTP methods and reports the user selection',
      (tester) async {
    OtpVerificationMethod? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OtpMethodSelector(
          selectedMethod: selected,
          onChanged: (method) => selected = method,
        ),
      ),
    ));

    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Mensaje SMS'), findsOneWidget);
    expect(find.text('Aplicación autenticadora'), findsOneWidget);

    await tester.tap(find.byKey(const Key('otp-method-sms')));
    await tester.pump();

    expect(selected, OtpVerificationMethod.sms);
  });

  testWidgets('does not allow choosing a method unavailable on the website',
      (tester) async {
    OtpVerificationMethod? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OtpMethodSelector(
          selectedMethod: selected,
          availableMethods: const {OtpVerificationMethod.email},
          onChanged: (method) => selected = method,
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('otp-method-sms')));
    await tester.pump();

    expect(selected, isNull);
    expect(find.text('No ofrecido por esta página.'), findsNWidgets(2));
  });
}
