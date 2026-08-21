import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../application/auth_providers.dart';

class InactiveUserScreen extends ConsumerWidget {
  const InactiveUserScreen({super.key, this.missingProfile = false});

  final bool missingProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  missingProfile
                      ? Icons.person_search_outlined
                      : Icons.person_off_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 18),
                Text(
                  missingProfile ? 'Perfil pendiente' : 'Usuario desactivado',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  missingProfile
                      ? 'La cuenta existe en Authentication, pero aún no tiene un perfil en Firestore. Solicite al administrador crear users/{uid}.'
                      : 'Su cuenta no tiene acceso a la aplicación. Contacte al administrador de Gestión Interna.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await ref
                          .read(notificationServiceProvider)
                          .prepareForLogout();
                    } finally {
                      await ref.read(authRepositoryProvider)?.signOut();
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
