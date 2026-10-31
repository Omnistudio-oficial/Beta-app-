import 'dart:convert';

import 'package:flutter/material.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  final TextEditingController _inputController = TextEditingController();
  String? _output;
  String? _error;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _convertCsvToJson() {
    try {
      final rows = CsvToJsonConverter.convert(_inputController.text);
      setState(() {
        _output = const JsonEncoder.withIndent('  ').convert(rows);
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _output = null;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Converter')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Convertir CSV a JSON', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Pega un CSV con encabezados en la primera fila. La conversión se realiza en este dispositivo.'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('converter-input'),
              controller: _inputController,
              minLines: 5,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Contenido CSV',
                hintText: 'nombre,edad\nAna,20',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('convert-csv-json'),
                onPressed: _inputController.text.trim().isEmpty ? null : _convertCsvToJson,
                icon: const Icon(Icons.sync_alt),
                label: const Text('Convertir a JSON'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, key: const Key('converter-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_output != null) ...[
              const SizedBox(height: 20),
              const Text('Resultado JSON', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SelectableText(_output!, key: const Key('converter-output')),
            ],
          ],
        ),
      ),
    );
  }
}

class CsvToJsonConverter {
  const CsvToJsonConverter._();

  static List<Map<String, String>> convert(String input) {
    if (input.trim().isEmpty) {
      throw const FormatException('Pega el contenido CSV para convertirlo.');
    }
    final rows = _parseRows(input);
    while (rows.isNotEmpty && rows.last.length == 1 && rows.last.single.isEmpty) {
      rows.removeLast();
    }
    if (rows.length < 2) {
      throw const FormatException('El CSV debe incluir encabezados y al menos una fila.');
    }
    final headers = rows.first.map((value) => value.trim()).toList();
    if (headers.any((header) => header.isEmpty)) {
      throw const FormatException('Cada columna necesita un encabezado.');
    }
    if (headers.toSet().length != headers.length) {
      throw const FormatException('Los encabezados del CSV no pueden repetirse.');
    }
    final result = <Map<String, String>>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.length != headers.length) {
        throw FormatException('La fila ${rowIndex + 1} tiene ${row.length} columnas; se esperaban ${headers.length}.');
      }
      result.add({for (var column = 0; column < headers.length; column++) headers[column]: row[column]});
    }
    return result;
  }

  static List<List<String>> _parseRows(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var afterQuote = false;
    var fieldStarted = false;

    void finishField() {
      row.add(field.toString());
      field.clear();
      inQuotes = false;
      afterQuote = false;
      fieldStarted = false;
    }

    void finishRow() {
      finishField();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
            afterQuote = true;
          }
        } else {
          field.write(char);
        }
        continue;
      }
      if (afterQuote) {
        if (char == ',') {
          finishField();
        } else if (char == '\n' || char == '\r') {
          if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
          finishRow();
        } else {
          throw const FormatException('Hay texto inesperado después de cerrar comillas.');
        }
        continue;
      }
      if (char == '"') {
        if (fieldStarted || field.length > 0) {
          throw const FormatException('Las comillas deben abrir al inicio de un campo.');
        }
        inQuotes = true;
        fieldStarted = true;
      } else if (char == ',') {
        finishField();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        finishRow();
      } else {
        field.write(char);
        fieldStarted = true;
      }
    }
    if (inQuotes) throw const FormatException('El CSV tiene comillas sin cerrar.');
    if (row.isNotEmpty || field.isNotEmpty || afterQuote || fieldStarted) finishRow();
    return rows;
  }
}
