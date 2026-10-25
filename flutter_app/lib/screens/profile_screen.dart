import 'package:flutter/material.dart';

import 'package:beta_app/models/user_profile.dart';
import 'package:beta_app/services/auth_service.dart';
import 'package:beta_app/services/firestore_service.dart';
import 'package:beta_app/screens/profile_editor.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = _authService.currentUser;
    _nameController = TextEditingController(text: user?.displayName ?? 'Usuario');
    _emailController = TextEditingController(text: user?.email ?? '');
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _authService.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final profile = await _firestoreService.getUserProfile(user.uid);
      if (profile != null) {
        _nameController.text = profile.name;
        _emailController.text = profile.email;
      } else {
        _nameController.text = user.displayName ?? 'Usuario';
        _emailController.text = user.email ?? '';
      }
    } catch (_) {
      _showFeedback('No se pudo cargar el perfil. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = _authService.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final profile = UserProfile(
        uid: user.uid,
        name: _nameController.text.trim().isEmpty ? 'Usuario' : _nameController.text.trim(),
        email: _emailController.text.trim().isEmpty ? user.email ?? '' : _emailController.text.trim(),
      );

      await _firestoreService.saveUserProfile(profile);
      _showFeedback('Perfil guardado en Firestore');
    } catch (_) {
      _showFeedback('No se pudo guardar el perfil. Revisa tu conexión e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _signOut() async {
    await _authService.signOut();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: user == null
            ? const Center(
                child: Text('Inicia sesión para ver tu perfil'),
              )
            : ProfileEditor(
                nameController: _nameController,
                emailController: _emailController,
                isLoading: _isLoading,
                onSave: _saveProfile,
              ),
      ),
    );
  }
}
