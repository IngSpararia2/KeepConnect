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
    final templates = await ref
        .read(formTemplateRepositoryProvider)
        .watchTemplates()
        .first;
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
    final input = CreateTicketInput(
      title: _title.text,
      description: _description.text,
      location: _location.text,
      equipment: _equipment.text,
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
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
              TextField(
                key: const Key('ticket-location'),
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Ubicación / zona *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _equipment,
                decoration: const InputDecoration(
                  labelText: 'Equipo o máquina (opcional)',
                  prefixIcon: Icon(Icons.precision_manufacturing_outlined),
                ),
              ),
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
