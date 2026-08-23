import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/app_providers.dart';
import '../../../core/utils/date_time_formatters.dart';
import '../../maintenance/domain/ticket_enums.dart';
import '../domain/organization_models.dart';

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
    final now = DateTime.now();
    await ref
        .read(organizationRepositoryProvider)
        .saveCompany(
          Company(
            id: original?.id ?? const Uuid().v4(),
            name: name,
            active: original?.active ?? true,
            createdAt: original?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<Company>>(
        stream: ref.read(organizationRepositoryProvider).watchCompanies(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
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
                              await ref
                                  .read(organizationRepositoryProvider)
                                  .saveCompany(
                                    company.copyWith(
                                      active: !company.active,
                                      updatedAt: DateTime.now(),
                                    ),
                                  );
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
    final now = DateTime.now();
    await ref
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
            return Center(child: Text('${snapshot.error}'));
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
                      await ref
                          .read(organizationRepositoryProvider)
                          .saveArea(
                            area.copyWith(
                              active: !area.active,
                              updatedAt: DateTime.now(),
                            ),
                          );
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
    final now = DateTime.now();
    try {
      await ref
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
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
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
          return Center(child: Text('${snapshot.error}'));
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
                    onChanged: (active) => ref
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
    try {
      await ref
          .read(organizationRepositoryProvider)
          .saveUser(draft.user, newPassword: draft.password);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _reset(BuildContext context, WidgetRef ref, AppUser user) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(
        title: 'Restablecer contraseña · ${user.displayName}',
      ),
    );
    if (password != null) {
      await ref
          .read(organizationRepositoryProvider)
          .resetPassword(user.id, password);
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
        return Center(child: Text('${snapshot.error}'));
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
                        : '${user.operationalRole?.label} · ${user.areaAccessMode == AreaAccessMode.all ? 'Todas las áreas' : '${user.areaIds.length} área(s)'}',
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
                          await ref
                              .read(organizationRepositoryProvider)
                              .saveUser(_copyUser(user, active: !user.active));
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
    title: Text(widget.title),
    content: TextField(
      key: widget.fieldKey,
      controller: _controller,
      decoration: InputDecoration(labelText: 'Nombre', errorText: _error),
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
  String? _companyId;
  AppRole _role = AppRole.production;
  AreaAccessMode _mode = AreaAccessMode.all;
  Set<String> _selectedAreas = {};
  List<Company> _companies = [];
  List<WorkArea> _areas = [];
  @override
  void initState() {
    super.initState();
    _companyId = widget.user?.companyId;
    _role = widget.user?.operationalRole ?? AppRole.production;
    _mode = widget.user?.areaAccessMode ?? AreaAccessMode.all;
    _selectedAreas = {...?widget.user?.areaIds};
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    _companies = await ref
        .read(organizationRepositoryProvider)
        .watchCompanies(includeInactive: false)
        .first;
    _companyId ??= _companies.firstOrNull?.id;
    await _loadAreas();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadAreas() async {
    _areas = _companyId == null
        ? []
        : await ref
              .read(organizationRepositoryProvider)
              .watchAreas(_companyId!, includeInactive: false)
              .first;
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
    final now = DateTime.now();
    Navigator.pop(
      context,
      _UserDraft(
        AppUser(
          id: widget.user?.id ?? const Uuid().v4(),
          username: _username.text,
          displayName: _name.text,
          privilege: PlatformPrivilege.user,
          companyId: _companyId,
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.user == null ? 'Nuevo usuario' : 'Editar usuario'),
    content: SizedBox(
      width: 540,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('user-display-name'),
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  TextField(
                    key: const Key('user-username'),
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Usuario o correo',
                    ),
                  ),
                  if (widget.user == null)
                    TextField(
                      key: const Key('user-password'),
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña inicial',
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: _companyId,
                    decoration: const InputDecoration(labelText: 'Empresa'),
                    items: _companies
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      _companyId = value;
                      await _loadAreas();
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  DropdownButtonFormField<AppRole>(
                    initialValue: _role,
                    decoration: const InputDecoration(
                      labelText: 'Rol operativo',
                    ),
                    items: AppRole.values
                        .map(
                          (r) =>
                              DropdownMenuItem(value: r, child: Text(r.label)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _role = value ?? _role),
                  ),
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
                  if (_mode == AreaAccessMode.selected)
                    for (final area in _areas)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(area.name),
                        value: _selectedAreas.contains(area.id),
                        onChanged: (selected) => setState(() {
                          if (selected == true) {
                            _selectedAreas.add(area.id);
                          } else {
                            _selectedAreas.remove(area.id);
                          }
                        }),
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
      FilledButton(
        key: const Key('save-user'),
        onPressed: _loading ? null : _save,
        child: const Text('Guardar'),
      ),
    ],
  );
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
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
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
        TextField(
          controller: _confirmation,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
        ),
      ],
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
  companyId: user.companyId,
  operationalRole: user.operationalRole,
  active: active,
  areaAccessMode: user.areaAccessMode,
  areaIds: user.areaIds,
  createdAt: user.createdAt,
  updatedAt: DateTime.now(),
  lastSeenAt: user.lastSeenAt,
);
