import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'app_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class GestionInternaApp extends ConsumerStatefulWidget {
  const GestionInternaApp({super.key});
  @override
  ConsumerState<GestionInternaApp> createState() => _GestionInternaAppState();
}

class _GestionInternaAppState extends ConsumerState<GestionInternaApp> {
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref
        .read(notificationServiceProvider)
        .ticketIds
        .listen((id) => ref.read(appRouterProvider).go('/tickets/$id'));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: AppConfig.appName,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ref.watch(themeModeProvider),
    routerConfig: ref.watch(appRouterProvider),
  );
}
