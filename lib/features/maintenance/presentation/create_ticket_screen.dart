import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../app/app_providers.dart';
import '../application/form_template_providers.dart';
import '../domain/create_ticket_input.dart';
import '../domain/form_template.dart';
import '../domain/ticket_enums.dart';
import '../domain/ticket_question.dart';
import '../../organization/domain/organization_models.dart';
import 'widgets/question_editor.dart';

class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});
  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _equipment = TextEditingController();
  final _questions = <TicketQuestion>[];
  var _priority = TicketPriority.medium;
  var _saving = false;
  var _loadingCatalogs = true;
  String? _catalogError;
  List<CatalogItem> _locations = const [];
  List<CatalogItem> _equipmentItems = const [];
  String? _locationSelection;
  String? _equipmentSelection;

  static const _other = '__other__';

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadCatalogs);
  }

  Future<void> _loadCatalogs() async {
    final session = ref.read(sessionProvider);
    final repository = ref.read(organizationRepositoryProvider);
    if (mounted) {
      setState(() {
        _loadingCatalogs = true;
        _catalogError = null;
      });
    }
    try {
      final locations = await repository
          .watchCatalog(
            session.companyId!,
            session.areaId!,
            CatalogKind.location,
          )
          .first;
      final equipmentItems = await repository
          .watchCatalog(
            session.companyId!,
            session.areaId!,
            CatalogKind.equipment,
          )
          .first;
      if (!mounted) return;
      setState(() {
        _locations = locations;
        _equipmentItems = equipmentItems;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _catalogError =
              'No fue posible cargar los catálogos. Inténtalo de nuevo.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingCatalogs = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _equipment.dispose();
    super.dispose();
  }

  Future<void> _addQuestion() async {
    final question = await showQuestionEditor(context);
    if (question != null) setState(() => _questions.add(question));
  }

  Future<void> _editQuestion(int index) async {
    final edited = await showQuestionEditor(
      context,
      initial: _questions[index],
    );
    if (edited != null) setState(() => _questions[index] = edited);
  }

  Future<void> _selectTemplate() async {
    late final List<FormTemplate> templates;
    try {
      templates = await ref
          .read(formTemplateRepositoryProvider)
          .watchTemplates()
          .first;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No fue posible cargar los formularios prediseñados.',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay formularios prediseñados.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<FormTemplate>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: templates.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Seleccionar plantilla',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              );
            }
            final template = templates[index - 1];
            return Card(
              child: ListTile(
                key: ValueKey('select-template-${template.id}'),
                title: Text(template.name),
                subtitle: Text(
                  [
                    if (template.description?.isNotEmpty == true)
                      template.description!,
                    '${template.questions.length} pregunta${template.questions.length == 1 ? '' : 's'}',
                  ].join('\n'),
                ),
                onTap: () => Navigator.pop(context, template),
              ),
            );
          },
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _questions.addAll(selected.instantiateQuestions(() => const Uuid().v4()));
    });
  }

  Future<void> _save() async {
    final locationItem = _locations
        .where((item) => item.id == _locationSelection)
        .firstOrNull;
    final equipmentItem = _equipmentItems
        .where((item) => item.id == _equipmentSelection)
        .firstOrNull;
    final customLocation = _locationSelection == _other;
    final customEquipment = _equipmentSelection == _other;
    final input = CreateTicketInput(
      title: _title.text,
      description: _description.text,
      location: customLocation ? _location.text : locationItem?.name ?? '',
      locationOptionId: locationItem?.id,
      locationIsCustom: customLocation,
      equipment: customEquipment ? _equipment.text : equipmentItem?.name,
      equipmentOptionId: equipmentItem?.id,
      equipmentIsCustom: customEquipment,
      priority: _priority,
      questions: [
        for (var i = 0; i < _questions.length; i++)
          TicketQuestion(
            id: _questions[i].id,
            prompt: _questions[i].prompt,
            type: _questions[i].type,
            required: _questions[i].required,
            order: i,
            options: _questions[i].options,
          ),
      ],
    );
    final errors = input.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errors.join('\n'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(maintenanceRepositoryProvider)
          .createTicket(input);
      if (mounted) context.pushReplacement('/tickets/${result.ticketId}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No fue posible crear la solicitud.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nueva solicitud')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                key: const Key('ticket-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'Título *'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ticket-description'),
                controller: _description,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Descripción *'),
              ),
              const SizedBox(height: 12),
              if (_catalogError case final error?) ...[
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(child: Text(error)),
                        TextButton(
                          key: const Key('retry-ticket-catalogs'),
                          onPressed: _loadingCatalogs ? null : _loadCatalogs,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                key: const Key('ticket-location-catalog'),
                initialValue: _locationSelection,
                decoration: const InputDecoration(
                  labelText: 'Ubicación / zona *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                items: [
                  for (final item in _locations)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                  const DropdownMenuItem(value: _other, child: Text('Otra')),
                ],
                onChanged: _loadingCatalogs || _catalogError != null
                    ? null
                    : (value) => setState(() => _locationSelection = value),
              ),
              if (_locationSelection == _other) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('ticket-location-other'),
                  controller: _location,
                  decoration: const InputDecoration(
                    labelText: 'Ubicación personalizada *',
                  ),
                ),
                const _CustomValueWarning(),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('ticket-equipment-catalog'),
                initialValue: _equipmentSelection,
                decoration: const InputDecoration(
                  labelText: 'Equipo o máquina (opcional)',
                  prefixIcon: Icon(Icons.precision_manufacturing_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Sin equipo'),
                  ),
                  for (final item in _equipmentItems)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                  const DropdownMenuItem(value: _other, child: Text('Otra')),
                ],
                onChanged: _loadingCatalogs || _catalogError != null
                    ? null
                    : (value) => setState(() => _equipmentSelection = value),
              ),
              if (_equipmentSelection == _other) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('ticket-equipment-other'),
                  controller: _equipment,
                  decoration: const InputDecoration(
                    labelText: 'Equipo personalizado *',
                  ),
                ),
                const _CustomValueWarning(),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<TicketPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Prioridad'),
                items: TicketPriority.values
                    .map(
                      (priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: 22),
              Text(
                'Formulario para Mantenimiento',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (ref.watch(sessionProvider).effectiveRole ==
                      AppRole.production)
                    OutlinedButton.icon(
                      key: const Key('use-form-template'),
                      onPressed: _selectTemplate,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Usar formulario prediseñado'),
                    ),
                  OutlinedButton.icon(
                    key: const Key('add-question'),
                    onPressed: _addQuestion,
                    icon: const Icon(Icons.add),
                    label: const Text('Pregunta'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_questions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'No hay preguntas. El ticket podrá finalizarse normalmente.',
                    ),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _questions.length,
                  onReorderItem: (oldIndex, newIndex) => setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    _questions.insert(newIndex, _questions.removeAt(oldIndex));
                  }),
                  itemBuilder: (_, index) {
                    final question = _questions[index];
                    return Card(
                      key: ValueKey(question.id),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.drag_handle),
                        title: Text(question.prompt),
                        subtitle: Text(
                          '${question.type.label}${question.required ? ' · Obligatoria' : ''}',
                        ),
                        onTap: () => _editQuestion(index),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('edit-question-${question.id}'),
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editQuestion(index),
                            ),
                            IconButton(
                              key: ValueKey('delete-question-${question.id}'),
                              tooltip: 'Eliminar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  setState(() => _questions.removeAt(index)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('submit-ticket'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('Crear solicitud'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CustomValueWarning extends StatelessWidget {
  const _CustomValueWarning();

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: const Padding(
      padding: EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Usa “Otra” únicamente cuando ninguna opción existente aplique. '
              'Escribir valores manuales sin coordinación con el administrador puede producir '
              'inconsistencias y afectar el análisis estadístico futuro del histórico de solicitudes.',
            ),
          ),
        ],
      ),
    ),
  );
}
