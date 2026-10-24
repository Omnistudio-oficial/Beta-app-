import 'package:flutter/material.dart';

class ConverterScreen extends StatelessWidget {
  const ConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Converter')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Media converter',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Input value',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Choose output format'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: const [
                  Chip(label: Text('MP3')),
                  Chip(label: Text('PDF')),
                  Chip(label: Text('PNG')),
                  Chip(label: Text('MP4')),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.sync_alt),
                  label: const Text('Convert'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
