import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../app/theme/theme_mode_selector.dart';
import '../../../config/app_config.dart';
import '../../organization/data/password_hasher.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  bool _loadingBootstrap = true;
  bool _bootstrap = false;
  bool _bootstrapLoadFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadBootstrap);
  }

  Future<void> _loadBootstrap() async {
    if (mounted) {
      setState(() {
        _loadingBootstrap = true;
        _error = null;
        _bootstrapLoadFailed = false;
      });
    }
    try {
      final needed = await ref
          .read(authenticationRepositoryProvider)
          .needsBootstrap();
      if (mounted) {
        setState(() {
          _bootstrap = needed;
          _loadingBootstrap = false;
          _bootstrapLoadFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingBootstrap = false;
          _bootstrapLoadFailed = true;
          _error =
              'No fue posible comprobar la configuración inicial. Inténtalo de nuevo.';
        });
      }
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_bootstrap) {
      if (_displayName.text.trim().isEmpty || _user.text.trim().isEmpty) {
        setState(() => _error = 'Nombre y usuario son obligatorios.');
        return;
      }
      if (_password.text.length < PasswordHasher.minimumPasswordLength) {
        setState(
          () => _error =
              'La contraseña debe tener al menos ${PasswordHasher.minimumPasswordLength} caracteres.',
        );
        return;
      }
      if (_password.text != _confirmation.text) {
        setState(() => _error = 'Las contraseñas no coinciden.');
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_bootstrap) {
        await ref
            .read(sessionProvider.notifier)
            .bootstrap(
              username: _user.text,
              displayName: _displayName.text,
              password: _password.text,
            );
      } else {
        await ref
            .read(sessionProvider.notifier)
            .login(_user.text, _password.text);
      }
      if (mounted) {
        context.go('/areas');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _loginErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          Positioned(top: 4, right: 4, child: ThemeModeSelector()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _loadingBootstrap
                        ? const SizedBox(
                            height: 300,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _bootstrapLoadFailed
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                key: const Key('login-error'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                key: const Key('retry-bootstrap'),
                                onPressed: _loadBootstrap,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Image.asset(
                                'assets/branding/app_logo.png',
                                key: const Key('app-logo-login'),
                                height: 112,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _bootstrap
                                    ? 'Crear cuenta propietaria'
                                    : 'Gestión Interna',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _bootstrap
                                    ? 'Configuración segura de primer uso. Este acceso dejará de estar disponible al crear la cuenta.'
                                    : 'Solicitudes y trazabilidad de mantenimiento',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              if (_bootstrap) ...[
                                TextField(
                                  key: const Key('bootstrap-display-name'),
                                  controller: _displayName,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre del propietario',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextField(
                                key: const Key('login-user'),
                                controller: _user,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Usuario o correo',
                                  prefixIcon: Icon(Icons.alternate_email),
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
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              if (_bootstrap) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  key: const Key('bootstrap-confirm-password'),
                                  controller: _confirmation,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Confirmar contraseña',
                                    prefixIcon: Icon(Icons.lock_reset_outlined),
                                  ),
                                ),
                              ],
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    _error!,
                                    key: const Key('login-error'),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                key: Key(
                                  _bootstrap
                                      ? 'bootstrap-submit'
                                      : 'login-submit',
                                ),
                                onPressed: _submitting ? null : _submit,
                                icon: Icon(
                                  _bootstrap
                                      ? Icons.admin_panel_settings_outlined
                                      : Icons.login_rounded,
                                ),
                                label: Text(
                                  _bootstrap
                                      ? 'Crear superadministrador'
                                      : 'Iniciar sesión',
                                ),
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
        ],
      ),
    ),
  );
}

String _loginErrorMessage(Object error) {
  final message = error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
  if (message.contains('SqliteException') ||
      message.contains('UNIQUE constraint failed')) {
    return 'No fue posible completar la operación. Inténtalo de nuevo.';
  }
  return message.isEmpty || message.contains('Exception')
      ? 'No fue posible completar la operación. Inténtalo de nuevo.'
      : message;
}
