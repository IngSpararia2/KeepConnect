import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../features/auth/application/auth_providers.dart';
import 'app_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class GestionInternaApp extends ConsumerStatefulWidget {
  const GestionInternaApp({super.key});

  @override
  ConsumerState<GestionInternaApp> createState() => _GestionInternaAppState();
}

class _GestionInternaAppState extends ConsumerState<GestionInternaApp> {
  StreamSubscription<String>? _notificationSubscription;
  String? _pendingTicketId;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(notificationServiceProvider);
    _notificationSubscription = notifications.ticketIds.listen(_openTicket);
  }

  void _openTicket(String ticketId) {
    final auth = ref.read(authStateProvider).value;
    final profile = ref.read(currentUserProfileProvider).value;
    if (auth == null || profile == null || !profile.active) {
      _pendingTicketId = ticketId;
      return;
    }
    ref.read(appRouterProvider).go('/maintenance/tickets/$ticketId');
  }

  void _flushPendingTicket() {
    final ticketId = _pendingTicketId;
    if (ticketId == null) return;
    final auth = ref.read(authStateProvider).value;
    final profile = ref.read(currentUserProfileProvider).value;
    if (auth == null || profile == null || !profile.active) return;
    _pendingTicketId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(appRouterProvider).go('/maintenance/tickets/$ticketId');
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      if (previous?.value?.uid != next.value?.uid && next.value != null) {
        unawaited(
          ref.read(notificationServiceProvider).requestNotificationPermission(),
        );
      }
      _flushPendingTicket();
    });
    ref.listen(currentUserProfileProvider, (_, _) => _flushPendingTicket());
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
