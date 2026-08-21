import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../domain/create_ticket_input.dart';
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Formulario para Mantenimiento',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              setState(() => _questions.removeAt(index)),
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
