import 'package:flutter/material.dart';

/// Reusable profile editor presentation, kept independent from Firebase so
/// the form can be exercised with a local callback in widget tests.
class ProfileEditor extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final bool isLoading;
  final VoidCallback onSave;

  const ProfileEditor({
    super.key,
    required this.nameController,
    required this.emailController,
    required this.isLoading,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 38,
          child: Icon(Icons.person, size: 38),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('profile-name'),
          controller: nameController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('profile-email'),
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
          enabled: false,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('save-profile'),
          onPressed: isLoading ? null : onSave,
          icon: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(isLoading ? 'Guardando...' : 'Guardar perfil'),
        ),
      ],
    );
  }
}
