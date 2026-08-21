import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/maintenance/presentation/area_selection_screen.dart';
import '../features/maintenance/presentation/app_shell.dart';
import '../features/maintenance/presentation/create_ticket_screen.dart';
import '../features/maintenance/presentation/ticket_detail_screen.dart';
import 'app_providers.dart';

final appRouterProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/area', builder: (_, _) => const AreaSelectionScreen()),
      GoRoute(path: '/home', builder: (_, _) => const AppShell()),
      GoRoute(
        path: '/tickets/new',
        builder: (_, _) => const CreateTicketScreen(),
      ),
      GoRoute(
        path: '/tickets/:ticketId',
        builder: (_, state) =>
            TicketDetailScreen(ticketId: state.pathParameters['ticketId']!),
      ),
    ],
  ),
);

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      final selected = ref.read(sessionProvider).areaSelected;
      context.go(selected ? '/home' : '/area');
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.precision_manufacturing_rounded, size: 76),
            SizedBox(height: 18),
            Text(
              'Gestión Interna',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 22),
            CircularProgressIndicator(),
            SizedBox(height: 36),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'App desarrollada por Ing. Samuel Parariá - Derechos Reservados',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
