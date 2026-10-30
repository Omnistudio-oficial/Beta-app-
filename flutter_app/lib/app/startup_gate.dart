import 'package:flutter/material.dart';

/// Keeps a visible Flutter screen on display while required services initialize.
/// The initializer and destination are injectable so startup behavior can be
/// tested without Firebase or a platform channel.
class StartupGate extends StatefulWidget {
  const StartupGate({
    required this.initialize,
    required this.appBuilder,
    super.key,
  });

  final Future<void> Function() initialize;
  final WidgetBuilder appBuilder;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _loading = true;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      await widget.initialize();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.appBuilder(context);

    return MaterialApp(
      title: 'OmniStudio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'OmniStudio',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  if (_loading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Preparando la aplicación…'),
                  ] else ...[
                    const Text(
                      'No se pudo iniciar la aplicación. Comprueba tu conexión e inténtalo de nuevo.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _initialize,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
