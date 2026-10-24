import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flutter_dash, size: 72, color: Colors.deepPurple),
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Cargando OmniStudio...'),
          ],
        ),
      ),
    );
  }
}
