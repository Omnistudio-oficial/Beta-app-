import 'package:flutter/material.dart';

class AIScreen extends StatelessWidget {
  const AIScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI workspace', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: const [
                    _PromptCard(prompt: 'Summarize this app state', icon: Icons.auto_awesome),
                    _PromptCard(prompt: 'Generate product notes', icon: Icons.note_alt_outlined),
                    _PromptCard(prompt: 'Draft onboarding copy', icon: Icons.edit_note_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final String prompt;
  final IconData icon;

  const _PromptCard({required this.prompt, required this.icon});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: Colors.deepPurple),
          title: Text(prompt),
          trailing: const Icon(Icons.arrow_forward_ios),
        ),
      );
}
