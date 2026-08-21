import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/firebase/firebase_providers.dart';

class SetupRequiredScreen extends ConsumerWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(firebaseBootstrapProvider);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 54,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Firebase todavía no está configurado',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      result.message ??
                          'Conecte un proyecto Firebase o inicie Emulator Suite.',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Opción A · Firebase real',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const SelectableText(
                      'firebase login\nflutterfire configure --platforms=android\nflutter run',
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Opción B · Emuladores locales',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const SelectableText(
                      'firebase emulators:start\nflutter run --dart-define=USE_FIREBASE_EMULATORS=true',
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Consulte docs/FIREBASE_SETUP.md para el procedimiento completo desde cero.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
