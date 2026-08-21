import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../config/app_config.dart';
import '../../../core/session/local_session.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  var _role = AccountRole.production;
  var _obscurePassword = true;
  var _submitting = false;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _submitting = true);
    await ref.read(sessionProvider.notifier).login(_role);
    if (mounted) context.go('/areas');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.precision_manufacturing_rounded,
                      size: 62,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Gestión Interna',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Solicitudes y trazabilidad de mantenimiento',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('login-user'),
                      controller: _user,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Usuario o correo',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('login-password'),
                      controller: _password,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AccountRole>(
                      key: const Key('account-role'),
                      initialValue: _role,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de usuario',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: AccountRole.values
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(role.label),
                            ),
                          )
                          .toList(),
                      onChanged: (role) =>
                          setState(() => _role = role ?? _role),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Selección de rol disponible únicamente en el prototipo.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const Key('login-submit'),
                      onPressed: _submitting ? null : _login,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Iniciar sesión'),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      AppConfig.credits,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
