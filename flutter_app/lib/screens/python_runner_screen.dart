import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Runs small Python snippets in a dedicated Web Worker using Pyodide.
/// User code is never sent to AI Agent Ultimate, Firebase, or Supabase.
class PythonRunnerScreen extends StatefulWidget {
  const PythonRunnerScreen({super.key, this.initialCode});

  /// Optional Python snippet suggested by Sara. It is never executed automatically.
  final String? initialCode;

  @override
  State<PythonRunnerScreen> createState() => _PythonRunnerScreenState();
}

class _PythonRunnerScreenState extends State<PythonRunnerScreen> {
  static const _sample = '''from math import sqrt

numbers = [4, 9, 16, 25]
print("Hola desde Python")
print("Raíces:", [sqrt(number) for number in numbers])
print("Total:", sum(numbers))''';

  late final TextEditingController _codeController;
  final WebViewController _webViewController = WebViewController();

  bool _runtimeReady = false;
  bool _running = false;
  String _status = 'Preparando el entorno Python…';
  String _output = '';

  @override
  void initState() {
    super.initState();
    final suggestedCode = widget.initialCode?.trim();
    _codeController = TextEditingController(
      text: suggestedCode != null && suggestedCode.isNotEmpty
          ? suggestedCode
          : _sample,
    );
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    await _webViewController
        .setJavaScriptMode(JavaScriptMode.unrestricted);
    await _webViewController.addJavaScriptChannel(
      'PythonRunner',
      onMessageReceived: _handleRuntimeMessage,
    );
    await _webViewController.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final scheme = Uri.tryParse(request.url)?.scheme;
          return scheme == 'file' || scheme == 'about'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (!mounted || error.isForMainFrame != true) return;
          setState(() {
            _runtimeReady = false;
            _running = false;
            _status = 'No se pudo abrir el entorno local de Python.';
          });
        },
      ),
    );
    await _webViewController.setBackgroundColor(Colors.transparent);
    await _webViewController.loadFlutterAsset(
      'assets/python_runner/index.html',
    );
  }

  void _handleRuntimeMessage(JavaScriptMessage message) {
    if (!mounted) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'];
      setState(() {
        switch (type) {
          case 'loading':
            _runtimeReady = false;
            _running = false;
            _status = 'Descargando e iniciando Python por primera vez…';
            break;
          case 'ready':
            _runtimeReady = true;
            _running = false;
            _status = widget.initialCode?.trim().isNotEmpty == true
                ? 'Python listo · revisa el código de Sara antes de ejecutarlo'
                : 'Python listo · ejecución local';
            break;
          case 'running':
            _running = true;
            _status = 'Ejecutando código…';
            _output = '';
            break;
          case 'result':
            _running = false;
            final stdout = decoded['stdout'] is String
                ? decoded['stdout'] as String
                : '';
            final stderr = decoded['stderr'] is String
                ? decoded['stderr'] as String
                : '';
            final error = decoded['error'] is String
                ? decoded['error'] as String
                : '';
            final parts = <String>[
              if (stdout.isNotEmpty) stdout,
              if (stderr.isNotEmpty) 'Errores / avisos:\n$stderr',
              if (error.isNotEmpty) 'Error:\n$error',
              if (decoded['truncated'] == true)
                '[Salida limitada a 12.000 caracteres.]',
            ];
            _output = parts.isEmpty
                ? 'Ejecución finalizada sin salida. Usa print() para mostrar resultados.'
                : parts.join('\n');
            _status = error.isEmpty
                ? 'Ejecución finalizada'
                : 'El código terminó con un error';
            break;
          case 'timeout':
            _runtimeReady = false;
            _running = false;
            _status = 'Ejecución detenida por superar 5 segundos.';
            _output = decoded['error']?.toString() ?? _status;
            break;
          case 'init_error':
            _runtimeReady = false;
            _running = false;
            _status = 'No se pudo iniciar Python.';
            _output = decoded['error']?.toString() ??
                'Comprueba tu conexión e inténtalo de nuevo.';
            break;
        }
      });
    } on FormatException {
      setState(() {
        _running = false;
        _status = 'Respuesta no válida del entorno Python.';
      });
    }
  }

  Future<void> _runCode() async {
    final code = _codeController.text;
    if (code.trim().isEmpty || !_runtimeReady || _running) return;
    if (code.length > 12000) {
      setState(() {
        _output = 'El código supera el límite de 12.000 caracteres.';
        _status = 'Código demasiado largo';
      });
      return;
    }
    try {
      await _webViewController.runJavaScript(
        'window.runPython(${jsonEncode(code)});',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _status = 'No se pudo enviar el código al entorno local.';
      });
    }
  }

  void _loadExample() {
    setState(() {
      _codeController.text = _sample;
      _output = '';
      _status = _runtimeReady
          ? 'Python listo · ejecución local'
          : 'Preparando el entorno Python…';
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ejecutor Python local'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.initialCode?.trim().isNotEmpty == true)
                  Card(
                    key: const Key('sara-python-suggestion'),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sara preparó este código. Revísalo primero; no se ejecutará hasta que pulses «Ejecutar Python».',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, color: colors.primary),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Ejecución en el dispositivo',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Python se ejecuta en un Web Worker local. El código no se envía a los servidores de OmniStudio. La primera carga descarga Pyodide desde jsDelivr y requiere Internet.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Límites: 12.000 caracteres y 5 segundos por ejecución. Red, acceso a archivos del dispositivo y módulos no permitidos están bloqueados. No es un sandbox reforzado para código malicioso; evita pegar contraseñas o datos privados.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Código Python',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _running ? null : _loadExample,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Ejemplo'),
                    ),
                  ],
                ),
                TextField(
                  key: const Key('python-code-input'),
                  controller: _codeController,
                  minLines: 10,
                  maxLines: 18,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                    hintText: 'Escribe código Python…',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('python-run-button'),
                  onPressed: _runtimeReady && !_running ? _runCode : null,
                  icon: _running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_running ? 'Ejecutando…' : 'Ejecutar Python'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      _runtimeReady
                          ? Icons.check_circle_outline
                          : Icons.hourglass_top,
                      size: 18,
                      color: _runtimeReady ? colors.primary : colors.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status)),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Resultado',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _output.isEmpty
                              ? 'La salida de Python aparecerá aquí.'
                              : _output,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Keep the local WebView mounted as the hidden runtime host.
            Positioned(
              left: 0,
              bottom: 0,
              child: SizedBox(
                width: 1,
                height: 1,
                child: WebViewWidget(controller: _webViewController),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
