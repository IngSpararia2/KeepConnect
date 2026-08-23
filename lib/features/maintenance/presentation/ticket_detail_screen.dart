import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../core/utils/date_time_formatters.dart';
import '../../../shared/widgets/priority_badge.dart';
import '../../../shared/widgets/status_badge.dart';
import '../application/maintenance_providers.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/status_transition_policy.dart';
import '../domain/ticket_enums.dart';
import '../domain/ticket_question.dart';
import 'widgets/question_editor.dart';

class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({required this.ticketId, super.key});
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(ticketProvider(ticketId))
      .when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, _) => Scaffold(
          appBar: AppBar(),
          body: Center(child: Text('$error')),
        ),
        data: (ticket) => ticket == null
            ? Scaffold(
                appBar: AppBar(),
                body: const Center(child: Text('La solicitud no existe.')),
              )
            : _TicketDetail(ticket: ticket),
      );
}

class _TicketDetail extends ConsumerWidget {
  const _TicketDetail({required this.ticket});
  final MaintenanceTicket ticket;

  Future<void> _advance(
    BuildContext context,
    WidgetRef ref,
    AppRole role,
  ) async {
    final next = StatusTransitionPolicy.next(ticket.status, role);
    if (next == null) return;
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .changeStatus(ticket.id, next, role);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Estado: ${next.label}')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _addQuestion(BuildContext context, WidgetRef ref) async {
    final question = await showQuestionEditor(context);
    if (question == null || !context.mounted) return;
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .addQuestion(ticket.id, question, AppRole.production);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider).effectiveRole;
    final next = StatusTransitionPolicy.next(ticket.status, role);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const Key('ticket-back'),
            tooltip: 'Atrás',
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(ticket.humanCode),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Detalle'),
              Tab(text: 'Actualizaciones'),
              Tab(text: 'Historial'),
            ],
          ),
          actions: [
            if (role == AppRole.production &&
                ticket.status != TicketStatus.closed)
              IconButton(
                tooltip: 'Añadir pregunta',
                onPressed: () => _addQuestion(context, ref),
                icon: const Icon(Icons.playlist_add),
              ),
          ],
        ),
        body: TabBarView(
          children: [
            _DetailTab(ticket: ticket, role: role),
            _UpdatesTab(ticket: ticket, role: role),
            _HistoryTab(ticketId: ticket.id),
          ],
        ),
        bottomNavigationBar: next == null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  key: const Key('advance-status'),
                  onPressed: () => _advance(context, ref, role),
                  icon: Icon(
                    next == TicketStatus.closed
                        ? Icons.task_alt
                        : Icons.arrow_forward,
                  ),
                  label: Text(
                    next == TicketStatus.closed
                        ? 'Finalizar ticket'
                        : 'Cambiar a ${next.label}',
                  ),
                ),
              ),
      ),
    );
  }
}

class _DetailTab extends StatelessWidget {
  const _DetailTab({required this.ticket, required this.role});
  final MaintenanceTicket ticket;
  final AppRole role;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  PriorityBadge(ticket.priority),
                ],
              ),
              const SizedBox(height: 12),
              StatusBadge(ticket.status),
              const Divider(height: 28),
              Text(ticket.description),
              const SizedBox(height: 14),
              _Fact(Icons.location_on_outlined, ticket.location),
              if (ticket.equipment != null)
                _Fact(
                  Icons.precision_manufacturing_outlined,
                  ticket.equipment!,
                ),
              _Fact(
                Icons.schedule_outlined,
                'Creado ${AppDateTime.dateTime(ticket.createdAt)}',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Formulario',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: Icon(
            ticket.isFormComplete
                ? Icons.check_circle_outline
                : Icons.info_outline,
            size: 18,
          ),
          label: Text(
            ticket.isFormComplete
                ? 'Formulario completo'
                : 'Formulario incompleto',
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (ticket.questions.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Esta solicitud no tiene preguntas.'),
          ),
        )
      else if (role == AppRole.maintenance &&
          ticket.status != TicketStatus.closed)
        _AnswerForm(key: ValueKey(ticket.updatedAt), ticket: ticket)
      else
        for (final question in ticket.questions)
          _ReadOnlyAnswer(question: question),
    ],
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ReadOnlyAnswer extends StatelessWidget {
  const _ReadOnlyAnswer({required this.question});
  final TicketQuestion question;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${question.prompt}${question.required ? ' *' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            question.answer.isEmpty
                ? 'Sin respuesta'
                : question.answer.join(', '),
            style: TextStyle(
              color: question.answer.isEmpty
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AnswerForm extends ConsumerStatefulWidget {
  const _AnswerForm({required this.ticket, super.key});
  final MaintenanceTicket ticket;
  @override
  ConsumerState<_AnswerForm> createState() => _AnswerFormState();
}

class _AnswerFormState extends ConsumerState<_AnswerForm> {
  late final Map<String, List<String>> _answers = {
    for (final question in widget.ticket.questions)
      question.id: List.of(question.answer),
  };
  late final Map<String, TextEditingController> _controllers = {
    for (final question in widget.ticket.questions.where(
      (q) => q.type == QuestionType.freeText,
    ))
      question.id: TextEditingController(
        text: question.answer.firstOrNull ?? '',
      ),
  };
  var _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    for (final entry in _controllers.entries) {
      _answers[entry.key] = [entry.value.text.trim()];
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .saveAnswers(widget.ticket.id, _answers, AppRole.maintenance);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Progreso guardado.')));
      }
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
  Widget build(BuildContext context) => Column(
    children: [
      for (final question in widget.ticket.questions)
        Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${question.prompt}${question.required ? ' *' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (question.type == QuestionType.freeText)
                  TextField(
                    controller: _controllers[question.id],
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Escribe la respuesta',
                    ),
                  )
                else if (question.type == QuestionType.singleChoice)
                  RadioGroup<String>(
                    groupValue: _answers[question.id]?.firstOrNull,
                    onChanged: (value) => setState(
                      () =>
                          _answers[question.id] = value == null ? [] : [value],
                    ),
                    child: Column(
                      children: [
                        for (final option in question.options)
                          RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(option),
                            value: option,
                          ),
                      ],
                    ),
                  )
                else
                  for (final option in question.options)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(option),
                      value: _answers[question.id]?.contains(option) ?? false,
                      onChanged: (selected) => setState(() {
                        final values = _answers[question.id] ??= [];
                        selected == true
                            ? values.add(option)
                            : values.remove(option);
                      }),
                    ),
              ],
            ),
          ),
        ),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('save-progress'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar progreso'),
        ),
      ),
    ],
  );
}

class _UpdatesTab extends ConsumerWidget {
  const _UpdatesTab({required this.ticket, required this.role});
  final MaintenanceTicket ticket;
  final AppRole role;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final update = await showDialog<_UpdateDraft>(
      context: context,
      builder: (_) => _AddUpdateDialog(role: role),
    );
    if (update != null) {
      try {
        await ref
            .read(maintenanceRepositoryProvider)
            .addUpdate(ticket.id, update.type, update.content, role);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(ticketUpdatesProvider(ticket.id))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) => Column(
          children: [
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Sin actualizaciones.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 9),
                          child: ListTile(
                            leading: Icon(
                              item.actor == AppRole.production
                                  ? Icons.factory_outlined
                                  : Icons.handyman_outlined,
                            ),
                            title: Text(item.type.label),
                            subtitle: Text(
                              '${item.content}\n${item.actor.label} · ${AppDateTime.dateTime(item.createdAt)}',
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (ticket.status != TicketStatus.closed)
              SafeArea(
                minimum: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _add(context, ref),
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('Añadir actualización'),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _UpdateDraft {
  const _UpdateDraft(this.type, this.content);
  final TicketUpdateType type;
  final String content;
}

class _AddUpdateDialog extends StatefulWidget {
  const _AddUpdateDialog({required this.role});
  final AppRole role;

  @override
  State<_AddUpdateDialog> createState() => _AddUpdateDialogState();
}

class _AddUpdateDialogState extends State<_AddUpdateDialog> {
  final _content = TextEditingController();
  late var _type = widget.role == AppRole.production
      ? TicketUpdateType.note
      : TicketUpdateType.observation;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: const Text('Añadir actualización'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<TicketUpdateType>(
              key: const Key('update-type'),
              initialValue: _type,
              items:
                  (widget.role == AppRole.production
                          ? [
                              TicketUpdateType.note,
                              TicketUpdateType.instruction,
                            ]
                          : [
                              TicketUpdateType.observation,
                              TicketUpdateType.action,
                            ])
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('update-content'),
              controller: _content,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Contenido'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        key: const Key('cancel-update'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('save-update'),
        onPressed: () =>
            Navigator.pop(context, _UpdateDraft(_type, _content.text)),
        child: const Text('Guardar'),
      ),
    ],
  );
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.ticketId});
  final String ticketId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(ticketEventsProvider(ticketId))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (events) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: events.length,
          itemBuilder: (_, index) {
            final event = events[index];
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(event.message),
              subtitle: Text(
                '${event.actor.label} · ${AppDateTime.dateTime(event.createdAt)}',
              ),
            );
          },
        ),
      );
}
