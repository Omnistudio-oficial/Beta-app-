import 'package:beta_app/screens/profile_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile editor keeps email read-only and submits edited name',
      (tester) async {
    final nameController = TextEditingController(text: 'Cristopher');
    final emailController = TextEditingController(text: 'user@example.com');
    var saveCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileEditor(
          nameController: nameController,
          emailController: emailController,
          isLoading: false,
          onSave: () => saveCalls++,
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('profile-name')), 'Chris');
    expect(nameController.text, 'Chris');
    expect(tester.widget<TextField>(find.byKey(const Key('profile-email'))).enabled,
        isFalse);
    await tester.tap(find.byKey(const Key('save-profile')));
    expect(saveCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    nameController.dispose();
    emailController.dispose();
  });

  testWidgets('profile editor disables saving and shows progress while busy',
      (tester) async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileEditor(
          nameController: nameController,
          emailController: emailController,
          isLoading: true,
          onSave: () {},
        ),
      ),
    ));

    expect(find.text('Guardando...'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('save-profile'))).onPressed,
        isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    nameController.dispose();
    emailController.dispose();
  });
}
