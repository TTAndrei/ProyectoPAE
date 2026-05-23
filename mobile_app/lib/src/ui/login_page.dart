import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_controller.dart';
import '../theme/app_theme.dart';
import 'widgets/app_button.dart';
import 'widgets/app_text_field.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final session = context.read<SessionController>();
    final success = await session.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted || success) {
      return;
    }

    final message = session.errorMessage ?? 'Login failed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF060913), // Deep space black
              Color(0xFF0F172A), // Dark slate
              Color(0xFF1E1B4B), // Deep indigo
              Color(0xFF311042), // Deep purple
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  AppTheme.primary, // Brand primary orange
                                  Color(0xFFF43F5E), // Rose
                                  AppTheme.tertiary, // Brand tertiary purple
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'PAE Mobile',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Gestión de rutas de última milla',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 32),
                            AppTextField(
                              controller: _usernameController,
                              labelText: 'Usuario',
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              style: const TextStyle(color: Colors.white),
                              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                              focusedBorderColor: Colors.white.withValues(alpha: 0.3),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Ingresa tu usuario';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            AppTextField(
                              controller: _passwordController,
                              obscureText: true,
                              labelText: 'Contraseña',
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              style: const TextStyle(color: Colors.white),
                              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                              focusedBorderColor: Colors.white.withValues(alpha: 0.3),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Ingresa tu contraseña';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: AppButton(
                                text: 'Entrar',
                                onPressed: session.isLoading ? null : _submit,
                                isLoading: session.isLoading,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Demo: central/central123, driver1/driver123, driver2/driver123',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.6),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
