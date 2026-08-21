import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/firebase/firebase_providers.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/inactive_user_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/maintenance/presentation/create_ticket_screen.dart';
import '../features/maintenance/presentation/maintenance_dashboard_screen.dart';
import '../features/maintenance/presentation/ticket_detail_screen.dart';
import '../features/maintenance/presentation/ticket_list_screen.dart';
import 'setup_required_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier();
  ref
    ..onDispose(refresh.dispose)
    ..listen(authStateProvider, (_, _) => refresh.refresh())
    ..listen(currentUserProfileProvider, (_, _) => refresh.refresh());

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final bootstrap = ref.read(firebaseBootstrapProvider);
      final location = state.matchedLocation;
      if (!bootstrap.isReady) {
        return location == '/setup-required' ? null : '/setup-required';
      }

      final authState = ref.read(authStateProvider);
      if (authState.isLoading) {
        return location == '/splash' ? null : '/splash';
      }
      final user = authState.value;
      final isPublic =
          location == '/login' ||
          location == '/forgot-password' ||
          location == '/setup-required';
      if (user == null) {
        return isPublic ? null : '/login';
      }

      final profileState = ref.read(currentUserProfileProvider);
      if (profileState.isLoading) {
        return location == '/splash' ? null : '/splash';
      }
      final profile = profileState.value;
      if (profile == null) {
        return location == '/profile-required' ? null : '/profile-required';
      }
      if (!profile.active) {
        return location == '/inactive' ? null : '/inactive';
      }
      if (isPublic ||
          location == '/splash' ||
          location == '/inactive' ||
          location == '/profile-required') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _SplashScreen()),
      GoRoute(
        path: '/setup-required',
        builder: (_, _) => const SetupRequiredScreen(),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/profile-required',
        builder: (_, _) => const InactiveUserScreen(missingProfile: true),
      ),
      GoRoute(path: '/inactive', builder: (_, _) => const InactiveUserScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/maintenance',
        builder: (_, _) => const MaintenanceDashboardScreen(),
      ),
      GoRoute(
        path: '/maintenance/tickets',
        builder: (_, state) => TicketListScreen(
          initialPreset: state.uri.queryParameters['preset'],
        ),
      ),
      GoRoute(
        path: '/maintenance/tickets/new',
        builder: (_, _) => const CreateTicketScreen(),
      ),
      GoRoute(
        path: '/maintenance/tickets/:ticketId',
        builder: (_, state) =>
            TicketDetailScreen(ticketId: state.pathParameters['ticketId']!),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      appBar: AppBar(title: const Text('Ruta no disponible')),
      body: Center(
        child: Text(state.error?.toString() ?? 'Pantalla no encontrada.'),
      ),
    ),
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.engineering_rounded, size: 64),
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Comprobando sesión…'),
          ],
        ),
      ),
    );
  }
}
