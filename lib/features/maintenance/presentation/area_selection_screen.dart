import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../config/app_config.dart';
import '../../organization/domain/organization_models.dart';

class AreaSelectionScreen extends ConsumerWidget {
  const AreaSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          session.isSuperAdmin
              ? 'Seleccionar empresa y área'
              : 'Seleccionar área',
        ),
        actions: [
          if (session.isSuperAdmin)
            IconButton(
              key: const Key('open-admin'),
              tooltip: 'Administración',
              onPressed: () => context.push('/admin'),
              icon: const Icon(Icons.admin_panel_settings_outlined),
            ),
          IconButton(
            key: const Key('logout-from-areas'),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<Company>>(
          stream: session.isSuperAdmin
              ? ref
                    .read(organizationRepositoryProvider)
                    .watchCompanies(includeInactive: false)
              : Stream.fromFuture(
                  ref
                      .read(organizationRepositoryProvider)
                      .getCompany(session.companyId!)
                      .then(
                        (company) => company == null ? <Company>[] : [company],
                      ),
                ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final companies = snapshot.data!;
            if (companies.isEmpty) {
              return _EmptyOrganization(isSuperAdmin: session.isSuperAdmin);
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Elige el contexto de trabajo',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                for (final company in companies)
                  _CompanyAreas(company: company),
                const SizedBox(height: 32),
                const Text(
                  AppConfig.credits,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompanyAreas extends ConsumerWidget {
  const _CompanyAreas({required this.company});
  final Company company;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<WorkArea>>(
        stream: ref
            .read(organizationRepositoryProvider)
            .watchAreas(company.id, includeInactive: false),
        builder: (context, snapshot) {
          final areas = snapshot.data ?? const <WorkArea>[];
          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    company.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator()
                  else if (areas.isEmpty)
                    const Text('No hay áreas activas disponibles.')
                  else
                    for (final area in areas)
                      ListTile(
                        key: ValueKey('select-area-${area.id}'),
                        leading: const CircleAvatar(
                          child: Icon(Icons.factory_outlined),
                        ),
                        title: Text(area.name),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          await ref
                              .read(sessionProvider.notifier)
                              .selectArea(company.id, area.id);
                          if (context.mounted) {
                            context.go('/home');
                          }
                        },
                      ),
                ],
              ),
            ),
          );
        },
      );
}

class _EmptyOrganization extends StatelessWidget {
  const _EmptyOrganization({required this.isSuperAdmin});
  final bool isSuperAdmin;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        isSuperAdmin
            ? 'Crea una empresa y sus áreas desde Administración para comenzar.'
            : 'No tienes áreas activas asignadas. Contacta al administrador.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
