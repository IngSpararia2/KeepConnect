import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/theme/app_theme.dart';
import 'package:gestion_interna/core/firebase/firebase_bootstrap.dart';
import 'package:gestion_interna/core/firebase/firebase_providers.dart';
import 'package:gestion_interna/features/auth/presentation/login_screen.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/shared/widgets/priority_badge.dart';

void main() {
  testWidgets('login muestra controles esenciales', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseBootstrapProvider.overrideWithValue(
            const FirebaseBootstrapResult(
              state: FirebaseBootstrapState.notConfigured,
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
      ),
    );

    expect(find.text('Gestión Interna'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('prioridad crítica usa texto e icono', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: PriorityBadge(TicketPriority.critical)),
      ),
    );

    expect(find.text('CRÍTICA'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
