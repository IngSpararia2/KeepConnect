import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../config/app_config.dart';
import '../../auth/application/auth_providers.dart';
import '../application/module_providers.dart';
import '../domain/app_module.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  var _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      try {
        await ref.read(notificationServiceProvider).prepareForLogout();
      } finally {
        await ref.read(authRepositoryProvider)?.signOut();
      }
      if (mounted) context.go('/login');
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final modules =
        ref.watch(activeModulesProvider).value ??
        const [AppModule.maintenanceFallback];
    final visibleModules = profile == null
        ? modules
        : modules.where((module) => module.isVisibleFor(profile.role)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _loggingOut ? null : _logout,
            icon: _loggingOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hola, ${profile?.name.split(' ').first ?? 'usuario'}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                profile == null
                    ? 'Seleccione un módulo'
                    : '${profile.role.label} · ${_departmentLabel(profile.departmentId)}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView.separated(
                      itemCount: visibleModules.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final module = visibleModules[index];
                        return _ModuleCard(
                          title: module.name,
                          description: module.description,
                          icon: _moduleIcon(module.iconKey),
                          onTap: () => context.go(module.route),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppConfig.credits,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _departmentLabel(String value) => switch (value) {
    AppConfig.productionDepartmentId => 'Planta de Producción',
    AppConfig.maintenanceDepartmentId => 'Mantenimiento',
    _ => value,
  };

  static IconData _moduleIcon(String key) => switch (key) {
    'maintenance' || 'tools' => Icons.home_repair_service_rounded,
    'quality' => Icons.verified_outlined,
    'laboratory' => Icons.science_outlined,
    'logistics' => Icons.local_shipping_outlined,
    'administration' => Icons.business_center_outlined,
    'safety' => Icons.health_and_safety_outlined,
    _ => Icons.apps_rounded,
  };
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 40, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward_ios_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
