import 'package:beta_app/screens/converter_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CsvToJsonConverter', () {
    test('converts headers and quoted comma fields', () {
      expect(
        CsvToJsonConverter.convert('name,note\nAna,"hola, mundo"'),
        [{'name': 'Ana', 'note': 'hola, mundo'}],
      );
    });

    test('supports escaped quotes and multiline values', () {
      expect(
        CsvToJsonConverter.convert('name,note\nAna,"dijo ""hola""\ny listo"'),
        [{'name': 'Ana', 'note': 'dijo "hola"\ny listo'}],
      );
    });

    test('rejects rows with the wrong number of columns', () {
      expect(
        () => CsvToJsonConverter.convert('name,age\nAna'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate headers', () {
      expect(
        () => CsvToJsonConverter.convert('name,name\nAna,Lu'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  testWidgets('converts CSV input and shows JSON result', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ConverterScreen()));
    await tester.enterText(find.byKey(const Key('converter-input')), 'name,age\nAna,20');
    await tester.pump();
    await tester.tap(find.byKey(const Key('convert-csv-json')));
    await tester.pump();
    expect(find.byKey(const Key('converter-output')), findsOneWidget);
    expect(find.textContaining('"name": "Ana"'), findsOneWidget);
  });

  testWidgets('shows validation message for malformed CSV', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ConverterScreen()));
    await tester.enterText(find.byKey(const Key('converter-input')), 'name,age\nAna');
    await tester.pump();
    await tester.tap(find.byKey(const Key('convert-csv-json')));
    await tester.pump();
    expect(find.byKey(const Key('converter-error')), findsOneWidget);
    expect(find.textContaining('se esperaban 2'), findsOneWidget);
  });
}
