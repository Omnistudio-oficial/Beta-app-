import 'package:flutter/material.dart';

void main() {
  runApp(const OmniStudioApp());
}

class OmniStudioApp extends StatelessWidget {
  const OmniStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniStudio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OmniStudio'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.flutter_dash,
                size: 72,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 24),
              const Text(
                'Flutter migration base',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'This project is the Flutter scaffold for migrating the Android app.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Start migration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
