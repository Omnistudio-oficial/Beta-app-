import 'package:flutter/material.dart';

class DocsScreen extends StatelessWidget {
  const DocsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Docs')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: const [
              _DocCard(title: 'Project migration guide', meta: 'Updated 2h ago'),
              _DocCard(title: 'Release notes', meta: 'Shared with team'),
              _DocCard(title: 'User onboarding', meta: 'Ready for review'),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final String title;
  final String meta;

  const _DocCard({required this.title, required this.meta});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined, color: Colors.blue),
        title: Text(title),
        subtitle: Text(meta),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
