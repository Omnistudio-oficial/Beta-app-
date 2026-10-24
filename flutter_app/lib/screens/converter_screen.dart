import 'package:flutter/material.dart';

class SocialScreen extends StatelessWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Social')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: const [
              _SocialCard(name: 'Alicia', status: 'Shared a new album'),
              _SocialCard(name: 'Mateo', status: 'Started a new project'),
              _SocialCard(name: 'Sofia', status: 'Joined the team chat'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialCard extends StatelessWidget {
  final String name;
  final String status;

  const _SocialCard({required this.name, required this.status});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(name.substring(0, 1)),
        ),
        title: Text(name),
        subtitle: Text(status),
      ),
    );
  }
}
