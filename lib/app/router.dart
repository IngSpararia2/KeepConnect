import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/maintenance/presentation/area_selection_screen.dart';
import '../features/maintenance/presentation/app_shell.dart';
import '../features/maintenance/presentation/create_ticket_screen.dart';
import '../features/maintenance/presentation/form_template_editor_screen.dart';
import '../features/maintenance/presentation/form_template_list_screen.dart';
import '../features/maintenance/presentation/login_screen.dart';
import '../features/maintenance/presentation/ticket_detail_screen.dart';
import '../features/organization/domain/organization_models.dart';
import '../features/organization/presentation/admin_screen.dart';
import 'app_providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier();
  ref
    ..onDispose(refresh.dispose)
    ..listen(sessionProvider, (_, _) => refresh.refresh());
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    errorBuilder: (_, _) => const InvalidRouteScreen(),
    redirect: (_, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;
      if (location == '/splash') return null;
      if (!session.loggedIn) return location == '/login' ? null : '/login';
      if (location == '/login') return '/areas';
      if (location.startsWith('/admin') && !session.isSuperAdmin) {
        return '/areas';
      }
      if (location.startsWith('/form-templates') && !session.isSuperAdmin) {
        return '/areas';
      }
      final requiresContext =
          location == '/home' ||
          location.startsWith('/tickets') ||
          location.startsWith('/form-templates');
      if (requiresContext &&
          (session.companyId == null || session.areaId == null)) {
        return '/areas';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/areas', builder: (_, _) => const AreaSelectionScreen()),
      GoRoute(path: '/home', builder: (_, _) => const AppShell()),
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
      GoRoute(
        path: '/admin/companies/:companyId',
        builder: (_, state) =>
            CompanyDetailScreen(companyId: state.pathParameters['companyId']!),
      ),
      GoRoute(
        path: '/admin/companies/:companyId/areas/:areaId/catalog/:kind',
        builder: (_, state) {
          final matches = CatalogKind.values.where(
            (value) => value.name == state.pathParameters['kind'],
          );
          final kind = matches.isEmpty ? null : matches.first;
          final companyId = state.pathParameters['companyId'];
          final areaId = state.pathParameters['areaId'];
          if (kind == null || companyId == null || areaId == null) {
            return const InvalidRouteScreen();
          }
          return CatalogAdminScreen(
            companyId: companyId,
            areaId: areaId,
            kind: kind,
          );
        },
      ),
      GoRoute(
        path: '/form-templates',
        builder: (_, _) => const FormTemplateListScreen(),
      ),
      GoRoute(
        path: '/form-templates/new',
        builder: (_, _) => const FormTemplateEditorScreen(),
      ),
      GoRoute(
        path: '/form-templates/:templateId/edit',
        builder: (_, state) => FormTemplateEditorScreen(
          templateId: state.pathParameters['templateId']!,
        ),
      ),
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
  );
});

class InvalidRouteScreen extends ConsumerWidget {
  const InvalidRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Ruta no disponible')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'La dirección solicitada no es válida o ya no está disponible.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(
                ref.read(sessionProvider).loggedIn ? '/areas' : '/login',
              ),
              child: const Text('Volver a un lugar seguro'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _redirectTimer;

  @override
  void initState() {
    super.initState();
    _redirectTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      context.go(ref.read(sessionProvider).loggedIn ? '/areas' : '/login');
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/branding/app_logo.png'),
              key: Key('app-logo-splash'),
              height: 132,
              fit: BoxFit.contain,
            ),
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
