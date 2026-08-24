import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/app_providers.dart';
import '../../../core/utils/date_time_formatters.dart';
import '../../maintenance/domain/ticket_enums.dart';
import '../domain/organization_models.dart';
import '../data/password_hasher.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Empresas'),
            Tab(text: 'Usuarios'),
          ],
        ),
      ),
      body: const TabBarView(children: [_CompaniesTab(), _UsersTab()]),
    ),
  );
}

class _CompaniesTab extends ConsumerWidget {
  const _CompaniesTab();
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    Company? original,
  ]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: original == null ? 'Nueva empresa' : 'Editar empresa',
        initial: original?.name,
        fieldKey: const Key('company-name'),
      ),
    );
    if (name == null) {
      return;
    }
    if (!context.mounted) return;
    final now = DateTime.now();
    await _runAdminAction(
      context,
      () => ref
          .read(organizationRepositoryProvider)
          .saveCompany(
            Company(
              id: original?.id ?? const Uuid().v4(),
              name: name,
              active: original?.active ?? true,
              createdAt: original?.createdAt ?? now,
              updatedAt: now,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<Company>>(
        stream: ref.read(organizationRepositoryProvider).watchCompanies(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No fue posible cargar las empresas.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final companies = snapshot.data!;
          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              key: const Key('create-company'),
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.add_business),
              label: const Text('Empresa'),
            ),
            body: companies.isEmpty
                ? const Center(child: Text('Aún no hay empresas.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: companies.length,
                    itemBuilder: (context, index) {
                      final company = companies[index];
                      return Card(
                        child: ListTile(
                          key: ValueKey('company-${company.id}'),
                          title: Text(company.name),
                          subtitle: Text(
                            company.active
                                ? 'Activa'
                                : 'Inactiva · conserva su histórico',
                          ),
                          onTap: () =>
                              context.push('/admin/companies/${company.id}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'edit') {
                                await _edit(context, ref, company);
                                return;
                              }
                              final saved = await _runAdminAction(
                                context,
                                () => ref
                                    .read(organizationRepositoryProvider)
                                    .saveCompany(
                                      company.copyWith(
                                        active: !company.active,
                                        updatedAt: DateTime.now(),
                                      ),
                                    ),
                              );
                              if (saved &&
                                  company.active &&
                                  ref.read(sessionProvider).companyId ==
                                      company.id) {
                                await ref
                                    .read(sessionProvider.notifier)
                                    .clearContext();
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Editar'),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(
                                  company.active ? 'Desactivar' : 'Activar',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      );
}

class CompanyDetailScreen extends ConsumerWidget {
  const CompanyDetailScreen({required this.companyId, super.key});
  final String companyId;
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    WorkArea? original,
  ]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: original == null ? 'Nueva área' : 'Editar área',
        initial: original?.name,
        fieldKey: const Key('area-name'),
      ),
    );
    if (name == null) {
      return;
    }
    if (!context.mounted) return;
    final now = DateTime.now();
    await _runAdminAction(
      context,
      () => ref
          .read(organizationRepositoryProvider)
          .saveArea(
            WorkArea(
              id: original?.id ?? const Uuid().v4(),
              companyId: companyId,
              name: name,
              active: original?.active ?? true,
              createdAt: original?.createdAt ?? now,
              updatedAt: now,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<Company?>(
    future: ref.read(organizationRepositoryProvider).getCompany(companyId),
    builder: (context, companySnapshot) => Scaffold(
      appBar: AppBar(title: Text(companySnapshot.data?.name ?? 'Empresa')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-area'),
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Área'),
      ),
      body: StreamBuilder<List<WorkArea>>(
        stream: ref.read(organizationRepositoryProvider).watchAreas(companyId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No fue posible cargar las áreas.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Crea el primer área de esta empresa.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final area = snapshot.data![index];
              return Card(
                child: ExpansionTile(
                  key: ValueKey('area-${area.id}'),
                  title: Text(area.name),
                  subtitle: Text(
                    area.active ? 'Activa' : 'Inactiva · conserva su histórico',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await _edit(context, ref, area);
                        return;
                      }
                      final saved = await _runAdminAction(
                        context,
                        () => ref
                            .read(organizationRepositoryProvider)
                            .saveArea(
                              area.copyWith(
                                active: !area.active,
                                updatedAt: DateTime.now(),
                              ),
                            ),
                      );
                      if (saved &&
                          area.active &&
                          ref.read(sessionProvider).areaId == area.id) {
                        await ref.read(sessionProvider.notifier).clearContext();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(area.active ? 'Desactivar' : 'Activar'),
                      ),
                    ],
                  ),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: const Text('Ubicaciones / zonas'),
                      onTap: () => context.push(
                        '/admin/companies/$companyId/areas/${area.id}/catalog/location',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.precision_manufacturing_outlined,
                      ),
                      title: const Text('Equipos / máquinas'),
                      onTap: () => context.push(
                        '/admin/companies/$companyId/areas/${area.id}/catalog/equipment',
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class CatalogAdminScreen extends ConsumerWidget {
  const CatalogAdminScreen({
    required this.companyId,
    required this.areaId,
    required this.kind,
    super.key,
  });
  final String companyId;
  final String areaId;
  final CatalogKind kind;
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    CatalogItem? original,
  ]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: original == null ? 'Nueva opción' : 'Editar opción',
        initial: original?.name,
        fieldKey: const Key('catalog-name'),
      ),
    );
    if (name == null) {
      return;
    }
    if (!context.mounted) return;
    final now = DateTime.now();
    await _runAdminAction(
      context,
      () => ref
          .read(organizationRepositoryProvider)
          .saveCatalogItem(
            CatalogItem(
              id: original?.id ?? const Uuid().v4(),
              companyId: companyId,
              areaId: areaId,
              kind: kind,
              name: name,
              active: original?.active ?? true,
              createdAt: original?.createdAt ?? now,
              updatedAt: now,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(kind.label)),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('create-catalog-item'),
      onPressed: () => _edit(context, ref),
      icon: const Icon(Icons.add),
      label: const Text('Opción'),
    ),
    body: StreamBuilder<List<CatalogItem>>(
      stream: ref
          .read(organizationRepositoryProvider)
          .watchCatalog(companyId, areaId, kind, includeInactive: true),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('No fue posible cargar el catálogo.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            for (final item in snapshot.data!)
              Card(
                child: ListTile(
                  title: Text(item.name),
                  subtitle: Text(
                    item.active
                        ? 'Activa'
                        : 'Retirada · disponible en el histórico',
                  ),
                  onTap: () => _edit(context, ref, item),
                  trailing: Switch(
                    value: item.active,
                    onChanged: (active) => _runAdminAction(
                      context,
                      () => ref
                          .read(organizationRepositoryProvider)
                          .saveCatalogItem(
                            item.copyWith(
                              active: active,
                              updatedAt: DateTime.now(),
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            const Card(
              child: ListTile(
                title: Text('Otra'),
                subtitle: Text(
                  'Opción sintética permanente; no editable ni eliminable.',
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    AppUser? original,
  ]) async {
    final draft = await showDialog<_UserDraft>(
      context: context,
      builder: (_) => _UserDialog(user: original),
    );
    if (draft == null) {
      return;
    }
    if (!context.mounted) return;
    await _runAdminAction(
      context,
      () => ref
          .read(organizationRepositoryProvider)
          .saveUser(draft.user, newPassword: draft.password),
    );
  }

  Future<void> _reset(BuildContext context, WidgetRef ref, AppUser user) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(
        title: 'Restablecer contraseña · ${user.displayName}',
      ),
    );
    if (password != null) {
      if (!context.mounted) return;
      await _runAdminAction(
        context,
        () => ref
            .read(organizationRepositoryProvider)
            .resetPassword(user.id, password),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => StreamBuilder<List<AppUser>>(
    stream: ref.read(organizationRepositoryProvider).watchUsers(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('No fue posible cargar los usuarios.'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('create-user'),
          onPressed: () => _edit(context, ref),
          icon: const Icon(Icons.person_add),
          label: const Text('Usuario'),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final user = snapshot.data![index];
            return Card(
              child: ListTile(
                title: Text(user.displayName),
                subtitle: Text(
                  [
                    user.username,
                    user.isSuperAdmin
                        ? 'Superadministrador'
                        : '${user.operationalRole?.label} · ${user.companyIds.length} empresa(s) · ${user.areaAccessMode == AreaAccessMode.all ? 'Todas las áreas' : '${user.areaIds.length} área(s)'}',
                    user.active ? 'Cuenta habilitada' : 'Cuenta deshabilitada',
                    if (user.lastSeenAt != null)
                      'Última actividad local: ${AppDateTime.dateTime(user.lastSeenAt!)}',
                  ].join('\n'),
                ),
                isThreeLine: true,
                trailing: user.isSuperAdmin
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'edit') {
                            await _edit(context, ref, user);
                            return;
                          }
                          if (action == 'reset') {
                            await _reset(context, ref, user);
                            return;
                          }
                          await _runAdminAction(
                            context,
                            () => ref
                                .read(organizationRepositoryProvider)
                                .saveUser(
                                  _copyUser(user, active: !user.active),
                                ),
                          );
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar'),
                          ),
                          const PopupMenuItem(
                            value: 'reset',
                            child: Text('Restablecer contraseña'),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(
                              user.active ? 'Deshabilitar' : 'Habilitar',
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.fieldKey,
    this.initial,
  });
  final String title;
  final Key fieldKey;
  final String? initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(widget.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        decoration: InputDecoration(labelText: 'Nombre', errorText: _error),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Guardar')),
    ],
  );
}

class _UserDraft {
  const _UserDraft(this.user, this.password);
  final AppUser user;
  final String? password;
}

class _UserDialog extends ConsumerStatefulWidget {
  const _UserDialog({this.user});
  final AppUser? user;
  @override
  ConsumerState<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<_UserDialog> {
  late final _name = TextEditingController(text: widget.user?.displayName);
  late final _username = TextEditingController(text: widget.user?.username);
  final _password = TextEditingController();
  bool _loading = true;
  Set<String> _companyIds = {};
  AppRole _role = AppRole.production;
  AreaAccessMode _mode = AreaAccessMode.all;
  Set<String> _selectedAreas = {};
  List<Company> _companies = [];
  List<WorkArea> _areas = [];
  String? _loadError;
  String? _validationError;
  @override
  void initState() {
    super.initState();
    _companyIds = {...?widget.user?.companyIds};
    _role = widget.user?.operationalRole ?? AppRole.production;
    _mode = widget.user?.areaAccessMode ?? AreaAccessMode.all;
    _selectedAreas = {...?widget.user?.areaIds};
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      _companies = await ref
          .read(organizationRepositoryProvider)
          .watchCompanies(includeInactive: true)
          .first;
      if (widget.user == null && _companyIds.isEmpty) {
        final firstActive = _companies.where((company) => company.active);
        if (firstActive.isNotEmpty) _companyIds.add(firstActive.first.id);
      }
      await _loadAreas();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadError =
              'No fue posible cargar empresas y áreas. Inténtalo de nuevo.';
          _loading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadAreas() async {
    _areas = [];
    for (final companyId in _companyIds) {
      _areas.addAll(
        await ref
            .read(organizationRepositoryProvider)
            .watchAreas(companyId, includeInactive: true)
            .first,
      );
    }
    _selectedAreas.removeWhere((id) => !_areas.any((area) => area.id == id));
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() {
    final username = _username.text.trim();
    final displayName = _name.text.trim();
    String? error;
    if (displayName.isEmpty) {
      error = 'El nombre es obligatorio.';
    } else if (username.isEmpty) {
      error = 'El usuario o correo es obligatorio.';
    } else if (widget.user == null && _password.text.isEmpty) {
      error = 'Define una contraseña inicial.';
    } else if (widget.user == null &&
        _password.text.length < PasswordHasher.minimumPasswordLength) {
      error =
          'La contraseña debe tener al menos ${PasswordHasher.minimumPasswordLength} caracteres.';
    } else if (_companyIds.isEmpty) {
      error = 'Selecciona al menos una empresa.';
    } else if (_mode == AreaAccessMode.selected && _selectedAreas.isEmpty) {
      error = 'Selecciona al menos un área.';
    } else {
      final selectedAreas = _areas.where(
        (area) => _selectedAreas.contains(area.id),
      );
      if (_mode == AreaAccessMode.selected &&
          (selectedAreas.length != _selectedAreas.length ||
              selectedAreas.any(
                (area) => !_companyIds.contains(area.companyId),
              ))) {
        error = 'Todas las áreas deben pertenecer a una empresa asignada.';
      } else if (_mode == AreaAccessMode.selected &&
          !_companyIds.every(
            (companyId) =>
                selectedAreas.any((area) => area.companyId == companyId),
          )) {
        error = 'Selecciona al menos un área de cada empresa asignada.';
      } else {
        final activeCompanies = _companies
            .where(
              (company) => _companyIds.contains(company.id) && company.active,
            )
            .map((company) => company.id)
            .toSet();
        final usable = _mode == AreaAccessMode.all
            ? _areas.any(
                (area) =>
                    activeCompanies.contains(area.companyId) && area.active,
              )
            : selectedAreas.any(
                (area) =>
                    activeCompanies.contains(area.companyId) && area.active,
              );
        if ((widget.user?.active ?? true) && !usable) {
          error =
              'El usuario activo debe tener al menos un contexto de trabajo disponible.';
        }
      }
    }
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      _UserDraft(
        AppUser(
          id: widget.user?.id ?? const Uuid().v4(),
          username: username,
          displayName: displayName,
          privilege: PlatformPrivilege.user,
          companyIds: _companyIds,
          operationalRole: _role,
          active: widget.user?.active ?? true,
          areaAccessMode: _mode,
          areaIds: _selectedAreas,
          createdAt: widget.user?.createdAt ?? now,
          updatedAt: now,
          lastSeenAt: widget.user?.lastSeenAt,
        ),
        _password.text.isEmpty ? null : _password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).vertical;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.user == null ? 'Nuevo usuario' : 'Editar usuario'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: availableHeight * .58,
        ),
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : _loadError != null
            ? SizedBox(
                height: 100,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('user-display-name'),
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    if (_validationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _validationError!,
                          key: const Key('user-dialog-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('user-username'),
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: 'Usuario o correo',
                      ),
                    ),
                    if (widget.user == null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('user-password'),
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña inicial',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Empresas asignadas',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    for (final company in _companies)
                      CheckboxListTile(
                        key: ValueKey('user-company-${company.id}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(company.name),
                        subtitle: company.active
                            ? null
                            : const Text('Empresa deshabilitada'),
                        value: _companyIds.contains(company.id),
                        onChanged:
                            (!company.active &&
                                !(widget.user?.companyIds.contains(
                                      company.id,
                                    ) ??
                                    false))
                            ? null
                            : (selected) async {
                                if (selected == true) {
                                  _companyIds.add(company.id);
                                } else {
                                  _companyIds.remove(company.id);
                                  _selectedAreas.removeWhere(
                                    (id) => _areas.any(
                                      (area) =>
                                          area.id == id &&
                                          area.companyId == company.id,
                                    ),
                                  );
                                }
                                try {
                                  await _loadAreas();
                                  if (mounted) {
                                    setState(() => _loadError = null);
                                  }
                                } catch (_) {
                                  if (mounted) {
                                    setState(() {
                                      _loadError =
                                          'No fue posible cargar las áreas. Inténtalo de nuevo.';
                                    });
                                  }
                                }
                              },
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AppRole>(
                      initialValue: _role,
                      decoration: const InputDecoration(
                        labelText: 'Rol operativo',
                      ),
                      items: AppRole.values
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(r.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _role = value ?? _role),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Acceso a todas las áreas'),
                      value: _mode == AreaAccessMode.all,
                      onChanged: (all) => setState(
                        () => _mode = all
                            ? AreaAccessMode.all
                            : AreaAccessMode.selected,
                      ),
                    ),
                    if (_mode == AreaAccessMode.selected) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Áreas permitidas',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      for (final company in _companies.where(
                        (company) => _companyIds.contains(company.id),
                      )) ...[
                        const SizedBox(height: 8),
                        Text(
                          company.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        for (final area in _areas.where(
                          (area) => area.companyId == company.id,
                        ))
                          CheckboxListTile(
                            key: ValueKey('user-area-${area.id}'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(area.name),
                            subtitle: area.active
                                ? null
                                : const Text('Área deshabilitada'),
                            value: _selectedAreas.contains(area.id),
                            onChanged:
                                (!area.active &&
                                    !(widget.user?.areaIds.contains(area.id) ??
                                        false))
                                ? null
                                : (selected) => setState(() {
                                    if (selected == true) {
                                      _selectedAreas.add(area.id);
                                    } else {
                                      _selectedAreas.remove(area.id);
                                    }
                                  }),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('save-user'),
          onPressed: _loading || _loadError != null ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title});
  final String title;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _save() {
    if (_password.text != _confirmation.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (_password.text.length < PasswordHasher.minimumPasswordLength) {
      setState(
        () => _error =
            'La contraseña debe tener al menos ${PasswordHasher.minimumPasswordLength} caracteres.',
      );
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(widget.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Nueva contraseña',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmation,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar contraseña',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Restablecer')),
    ],
  );
}

AppUser _copyUser(AppUser user, {required bool active}) => AppUser(
  id: user.id,
  username: user.username,
  displayName: user.displayName,
  privilege: user.privilege,
  companyIds: user.companyIds,
  operationalRole: user.operationalRole,
  active: active,
  areaAccessMode: user.areaAccessMode,
  areaIds: user.areaIds,
  createdAt: user.createdAt,
  updatedAt: DateTime.now(),
  lastSeenAt: user.lastSeenAt,
);

Future<bool> _runAdminAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminErrorMessage(error))));
    }
    return false;
  }
}

String _adminErrorMessage(Object error) {
  final message = error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
  if (message.contains('SqliteException') ||
      message.contains('UNIQUE constraint failed')) {
    return 'No fue posible completar la operación. Revisa los datos e inténtalo de nuevo.';
  }
  return message.isEmpty || message.contains('Exception')
      ? 'No fue posible completar la operación. Inténtalo de nuevo.'
      : message;
}
