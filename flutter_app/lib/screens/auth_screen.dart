import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:beta_app/services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.authService, this.onGoogleSignIn});

  final AuthService? authService;

  /// Injectable so widget tests can exercise Google sign-in without native UI.
  final Future<UserCredential?> Function()? onGoogleSignIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isRegisterMode = false;

  late final AuthService _authService = widget.authService ?? AuthService();

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final result = await (widget.onGoogleSignIn?.call() ??
          _authService.signInWithGoogle());
      if (result != null) _showMessage('Sesión iniciada correctamente');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'No se pudo iniciar sesión con Google');
    } catch (_) {
      _showMessage('No se pudo iniciar sesión con Google. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Email y contraseña son requeridos');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isRegisterMode) {
        await _authService.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        _showMessage('Cuenta creada correctamente');
      } else {
        await _authService.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        _showMessage('Sesión iniciada correctamente');
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Error de autenticación');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Auth'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isRegisterMode ? 'Crear cuenta' : 'Iniciar sesión',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_isRegisterMode) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        icon: const Text(
                          'G',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4285F4),
                          ),
                        ),
                        label: const Text('Iniciar sesión con Google'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('o continúa con tu correo'),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(
                      _isRegisterMode ? 'Crear cuenta' : 'Entrar',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() => _isRegisterMode = !_isRegisterMode);
                          },
                    child: Text(
                      _isRegisterMode
                          ? '¿Ya tienes cuenta? Inicia sesión'
                          : '¿No tienes cuenta? Regístrate',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
