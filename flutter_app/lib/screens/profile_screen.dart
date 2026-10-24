import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:beta_app/services/auth_service.dart';
import 'package:beta_app/services/firestore_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  bool _isLoading = false;
  String? _userName;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _authService.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final profile = await _firestoreService.getUserProfile(user.uid);
      setState(() {
        _userName = profile?.name ?? user.displayName ?? 'User';
        _userEmail = profile?.email ?? user.email ?? 'No email';
      });
    } catch (_) {
      setState(() {
        _userName = user.displayName ?? 'User';
        _userEmail = user.email ?? 'No email';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      setState(() => _isLoading = true);
      await _firestoreService.saveUserProfile(
        UserProfile(
          uid: user.uid,
          name: _userName ?? user.displayName ?? 'User',
          email: _userEmail ?? user.email ?? '',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved to Firestore')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
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
                child: Text('Please sign in to view your profile'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 38,
                    child: Icon(Icons.person, size: 38),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (value) => _userName = value,
                    controller: TextEditingController(text: _userName ?? user.displayName),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(labelText: 'Email'),
                    enabled: false,
                    controller: TextEditingController(text: _userEmail ?? user.email ?? ''),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _saveProfile,
                    icon: const Icon(Icons.save),
                    label: const Text('Save profile'),
                  ),
                ],
              ),
      ),
    );
  }
}
