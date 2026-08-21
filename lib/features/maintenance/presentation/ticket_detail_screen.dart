import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_time_formatters.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/priority_badge.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/app_user.dart';
import '../application/maintenance_providers.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/maintenance_settings.dart';
import '../domain/status_transition_policy.dart';
import '../domain/ticket_attachment.dart';
import '../domain/ticket_comment.dart';
import '../domain/ticket_enums.dart';
import '../domain/ticket_event.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({required this.ticketId, super.key});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  var _busy = false;
  final _picker = ImagePicker();

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppException.from(error).message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketValue = ref.watch(ticketProvider(widget.ticketId));
    final profileValue = ref.watch(currentUserProfileProvider);
    return AsyncValueView(
      value: ticketValue,
      onRetry: () => ref.invalidate(ticketProvider(widget.ticketId)),
      data: (ticket) {
        if (ticket == null) return const _TicketNotFound();
        final user = profileValue.value;
        if (user == null || !canReadTicket(user, ticket)) {
          return const _TicketAccessDenied();
        }
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(ticket.humanCode),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Detalle', icon: Icon(Icons.description_outlined)),
                  Tab(text: 'Conversación', icon: Icon(Icons.forum_outlined)),
                  Tab(text: 'Historial', icon: Icon(Icons.history_rounded)),
                ],
              ),
            ),
            body: Column(
              children: [
                _TicketHero(ticket: ticket),
                Expanded(
                  child: TabBarView(
                    children: [
                      _OverviewTab(
                        ticket: ticket,
                        onAddEvidence: () => _addEvidence(ticket),
                      ),
                      _ConversationTab(ticket: ticket, busy: _busy, run: _run),
                      _HistoryTab(ticketId: ticket.id),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: _TicketActions(
              ticket: ticket,
              user: user,
              busy: _busy,
              run: _run,
            ),
          ),
        );
      },
    );
  }

  Future<void> _addEvidence(MaintenanceTicket ticket) async {
    final maxPhotos =
        ref.read(maintenanceSettingsProvider).value?.maxPhotosPerTicket ??
        AppConfig.maxPhotosPerTicket;
    final current =
        ref.read(ticketAttachmentsProvider(ticket.id)).value ?? const [];
    if (current.length >= maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Este ticket ya tiene $maxPhotos fotografías.')),
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar fotografía'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Seleccionar de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
      requestFullMetadata: false,
    );
    if (image == null) return;
    await _run(() async {
      final service = ref.read(attachmentServiceProvider);
      if (service == null) {
        throw const AppException('Firebase Storage no está disponible.');
      }
      final uploaderUid = ref.read(currentUserProfileProvider).value?.uid;
      if (uploaderUid == null) {
        throw const AppException('No se pudo identificar al usuario.');
      }
      await service.uploadEvidence(
        ticketId: ticket.id,
        uploaderUid: uploaderUid,
        image: image,
      );
    });
  }
}

class _TicketHero extends StatelessWidget {
  const _TicketHero({required this.ticket});

  final MaintenanceTicket ticket;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    ticket.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PriorityBadge(ticket.priority, compact: true),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: StatusBadge(ticket.status)),
                Text(
                  ticket.createdAt == null
                      ? ''
                      : 'Abierto hace ${AppDateTime.elapsed(ticket.createdAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (ticket.productionStopped || ticket.safetyRisk) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (ticket.productionStopped)
                    const _AlertPill(
                      icon: Icons.factory_outlined,
                      text: 'PRODUCCIÓN DETENIDA',
                    ),
                  if (ticket.safetyRisk)
                    const _AlertPill(
                      icon: Icons.health_and_safety_outlined,
                      text: 'RIESGO DE SEGURIDAD',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlertPill extends StatelessWidget {
  const _AlertPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.ticket, required this.onAddEvidence});

  final MaintenanceTicket ticket;
  final VoidCallback onAddEvidence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments = ref.watch(ticketAttachmentsProvider(ticket.id));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        _Section(
          title: 'Solicitud',
          icon: Icons.description_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ticket.description),
              const Divider(height: 28),
              _DataRow(label: 'Solicitante', value: ticket.requesterName),
              _DataRow(label: 'Ubicación', value: ticket.location),
              _DataRow(
                label: 'Categoría',
                value: ticket.categoryName ?? ticket.categoryId,
              ),
              _DataRow(label: 'Activo', value: ticket.assetName ?? 'No aplica'),
              _DataRow(
                label: 'Afectación',
                value: ticket.impactPercent == null
                    ? 'No indicada'
                    : '${ticket.impactPercent} %',
              ),
              if (ticket.impactNotes?.isNotEmpty == true)
                _DataRow(label: 'Impacto', value: ticket.impactNotes!),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Asignación y tiempos',
          icon: Icons.assignment_ind_outlined,
          child: Column(
            children: [
              _DataRow(
                label: 'Responsable',
                value: ticket.primaryAssigneeName ?? 'Sin asignar',
              ),
              _DataRow(
                label: 'Creado',
                value: AppDateTime.dateTime(ticket.createdAt),
              ),
              _DataRow(
                label: 'Recibido',
                value: AppDateTime.dateTime(ticket.acknowledgedAt),
              ),
              _DataRow(
                label: 'Asignado',
                value: AppDateTime.dateTime(ticket.assignedAt),
              ),
              _DataRow(
                label: 'Trabajo iniciado',
                value: AppDateTime.dateTime(ticket.workStartedAt),
              ),
              _DataRow(
                label: 'Resuelto',
                value: AppDateTime.dateTime(ticket.resolvedAt),
              ),
              _DataRow(
                label: 'Cerrado',
                value: AppDateTime.dateTime(ticket.closedAt),
              ),
            ],
          ),
        ),
        if (ticket.diagnosis?.isNotEmpty == true ||
            ticket.workPerformed?.isNotEmpty == true ||
            ticket.resolutionNotes?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          _Section(
            title: 'Resolución',
            icon: Icons.task_alt_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ticket.diagnosis?.isNotEmpty == true)
                  _LongData(label: 'Diagnóstico', value: ticket.diagnosis!),
                if (ticket.workPerformed?.isNotEmpty == true)
                  _LongData(
                    label: 'Trabajo realizado',
                    value: ticket.workPerformed!,
                  ),
                if (ticket.resolutionNotes?.isNotEmpty == true)
                  _LongData(
                    label: 'Observaciones',
                    value: ticket.resolutionNotes!,
                  ),
              ],
            ),
          ),
        ],
        if (ticket.dynamicAnswers.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Section(
            title: 'Respuestas adicionales',
            icon: Icons.dynamic_form_outlined,
            child: Column(
              children: ticket.dynamicAnswers.entries
                  .map(
                    (entry) => _DataRow(
                      label: entry.key,
                      value: _displayDynamicValue(entry.value),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Section(
          title: 'Evidencias',
          icon: Icons.photo_library_outlined,
          trailing: IconButton(
            tooltip: 'Agregar evidencia',
            onPressed: ticket.isOpen ? onAddEvidence : null,
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
          child: attachments.when(
            data: (items) => items.isEmpty
                ? const Text('No hay fotografías adjuntas.')
                : _AttachmentGrid(items: items),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) =>
                const Text('No fue posible cargar las evidencias.'),
          ),
        ),
      ],
    );
  }

  static String _displayDynamicValue(Object? value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'Sí' : 'No';
    if (value is Iterable) return value.join(', ');
    return value.toString();
  }
}

class _AttachmentGrid extends ConsumerWidget {
  const _AttachmentGrid({required this.items});

  final List<TicketAttachment> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final attachment = items[index];
        return FutureBuilder<String>(
          future: ref
              .read(attachmentServiceProvider)
              ?.downloadUrl(attachment.storagePath),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Tooltip(
                message: 'No fue posible cargar esta imagen.',
                child: ColoredBox(
                  color: Color(0xFFE5E7EB),
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              );
            }
            final url = snapshot.data;
            return InkWell(
              onTap: url == null
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog.fullscreen(
                        child: Scaffold(
                          appBar: AppBar(title: Text(attachment.fileName)),
                          body: InteractiveViewer(
                            child: Center(child: Image.network(url)),
                          ),
                        ),
                      ),
                    ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: url == null
                    ? const ColoredBox(
                        color: Color(0xFFE5E7EB),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ConversationTab extends ConsumerStatefulWidget {
  const _ConversationTab({
    required this.ticket,
    required this.busy,
    required this.run,
  });

  final MaintenanceTicket ticket;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;

  @override
  ConsumerState<_ConversationTab> createState() => _ConversationTabState();
}

class _ConversationTabState extends ConsumerState<_ConversationTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await widget.run(() async {
      await ref
          .read(maintenanceRepositoryProvider)
          ?.addComment(ticketId: widget.ticket.id, text: text);
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(ticketCommentsProvider(widget.ticket.id));
    final uid = ref.watch(currentUserProfileProvider).value?.uid;
    return Column(
      children: [
        Expanded(
          child: comments.when(
            data: (items) => items.isEmpty
                ? const _NoComments()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _CommentBubble(
                      comment: items[index],
                      own: items[index].authorUid == uid,
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(
              child: Text('No fue posible cargar la conversación.'),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: widget.ticket.isOpen && !widget.busy,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: 'Escriba una actualización…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Enviar comentario',
                  onPressed: widget.ticket.isOpen && !widget.busy
                      ? _send
                      : null,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.comment, required this.own});

  final TicketComment comment;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: own ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(own ? 14 : 3),
            bottomRight: Radius.circular(own ? 3 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${comment.authorName} · ${comment.authorRole.label}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            const SizedBox(height: 5),
            Text(comment.text),
            const SizedBox(height: 5),
            Text(
              AppDateTime.dateTime(comment.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(ticketEventsProvider(ticketId));
    return events.when(
      data: (items) => items.isEmpty
          ? const Center(child: Text('Todavía no hay eventos registrados.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: items.length,
              itemBuilder: (context, index) => _EventTile(event: items[index]),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          const Center(child: Text('No se pudo cargar la auditoría.')),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final TicketEvent event;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 16,
                child: Icon(_eventIcon(event.type), size: 17),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.type.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (event.message.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(event.message),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${event.actorName} · ${AppDateTime.dateTime(event.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _eventIcon(TicketEventType type) => switch (type) {
    TicketEventType.created => Icons.add_task_rounded,
    TicketEventType.acknowledged => Icons.mark_email_read_outlined,
    TicketEventType.assigned => Icons.assignment_ind_outlined,
    TicketEventType.statusChanged => Icons.sync_alt_rounded,
    TicketEventType.priorityChanged => Icons.priority_high_rounded,
    TicketEventType.commentAdded => Icons.chat_bubble_outline_rounded,
    TicketEventType.attachmentAdded => Icons.add_a_photo_outlined,
    TicketEventType.urgencyEscalated => Icons.notification_important_outlined,
    TicketEventType.diagnosisAdded => Icons.biotech_outlined,
    TicketEventType.resolved => Icons.task_alt_rounded,
    TicketEventType.closed => Icons.lock_outline_rounded,
    TicketEventType.reopened => Icons.restart_alt_rounded,
    TicketEventType.cancelled => Icons.cancel_outlined,
    TicketEventType.productionImpactChanged => Icons.factory_outlined,
  };
}

class _TicketActions extends ConsumerWidget {
  const _TicketActions({
    required this.ticket,
    required this.user,
    required this.busy,
    required this.run,
  });

  final MaintenanceTicket ticket;
  final AppUser user;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(maintenanceSettingsProvider).value ??
        MaintenanceSettings.defaults;
    final isRequester = ticket.requesterUid == user.uid;
    final isAssignee =
        ticket.primaryAssigneeUid == user.uid ||
        ticket.participantUids.contains(user.uid) ||
        user.isAdmin;
    final targets = StatusTransitionPolicy.allowedTargets(
      from: ticket.status,
      role: user.role,
      isRequester: isRequester,
      isAssignee: isAssignee,
    );
    final canAssign =
        (user.isMaintenance || user.isAdmin) &&
        (ticket.status == TicketStatus.acknowledged ||
            ticket.status == TicketStatus.assigned);
    final showEscalate =
        (user.isAdmin || user.isProduction && isRequester) &&
        ticket.isOpen &&
        ticket.status != TicketStatus.resolved;
    final nextEscalationAt = ticket.lastManualEscalationAt?.add(
      Duration(minutes: settings.manualEscalationCooldownMinutes),
    );
    final cooldownRemaining = nextEscalationAt?.difference(DateTime.now());
    final escalationCoolingDown =
        cooldownRemaining != null && !cooldownRemaining.isNegative;
    final canEscalate = showEscalate && !escalationCoolingDown;
    final canChangePriority =
        (user.isMaintenance || user.isAdmin) && ticket.isOpen;
    final canUpdateProductionImpact =
        (user.isAdmin || user.isProduction && isRequester) && ticket.isOpen;

    if (targets.isEmpty &&
        !canAssign &&
        !showEscalate &&
        !canChangePriority &&
        !canUpdateProductionImpact) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        child: SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              if (showEscalate)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: busy || !canEscalate
                      ? null
                      : () => _escalate(context, ref),
                  icon: const Icon(Icons.notification_important_rounded),
                  label: Text(
                    escalationCoolingDown
                        ? 'Disponible en ${cooldownRemaining.inMinutes + 1} min'
                        : 'ESCALAR URGENCIA',
                  ),
                ),
              if (canAssign) ...[
                if (showEscalate) const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _assign(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Asignar'),
                ),
              ],
              if (canChangePriority) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _changePriority(context, ref),
                  icon: const Icon(Icons.priority_high_rounded),
                  label: const Text('Prioridad'),
                ),
              ],
              if (canUpdateProductionImpact) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _updateProductionImpact(context, ref),
                  icon: Icon(
                    ticket.productionStopped
                        ? Icons.play_circle_outline_rounded
                        : Icons.stop_circle_outlined,
                  ),
                  label: Text(
                    ticket.productionStopped
                        ? 'Producción reanudada'
                        : 'Reportar parada',
                  ),
                ),
              ],
              for (final target in targets.where(
                (item) => item != TicketStatus.assigned,
              )) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _transition(context, ref, target),
                  icon: Icon(_targetIcon(target)),
                  label: Text(_targetAction(target)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    TicketStatus target,
  ) async {
    if (target == TicketStatus.resolved) {
      final resolution = await showDialog<_ResolutionData>(
        context: context,
        builder: (_) => const _ResolveDialog(),
      );
      if (resolution == null) return;
      await run(
        () => ref
            .read(maintenanceRepositoryProvider)!
            .transitionTicket(
              ticketId: ticket.id,
              to: target,
              diagnosis: resolution.diagnosis,
              workPerformed: resolution.workPerformed,
              resolutionNotes: resolution.notes,
            ),
      );
      return;
    }

    String? reason;
    final requiresReason =
        target == TicketStatus.cancelled ||
        target == TicketStatus.waitingParts ||
        target == TicketStatus.waitingExternal ||
        target == TicketStatus.paused ||
        target == TicketStatus.inProgress &&
            ticket.status == TicketStatus.resolved;
    if (requiresReason) {
      reason = await _askReason(
        context,
        title: switch (target) {
          TicketStatus.cancelled => 'Cancelar solicitud',
          TicketStatus.waitingParts => 'Esperar repuesto',
          TicketStatus.waitingExternal => 'Registrar espera externa',
          TicketStatus.paused => 'Pausar trabajo',
          _ => 'Solicitar revisión nuevamente',
        },
      );
      if (reason == null) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_targetAction(target)),
          content: Text(
            'El ticket cambiará de “${ticket.status.label}” a “${target.label}”.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await run(
      () => ref
          .read(maintenanceRepositoryProvider)!
          .transitionTicket(ticketId: ticket.id, to: target, reason: reason),
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    late final List<AppUser> users;
    try {
      users = await ref.read(maintenanceUsersProvider.future);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppException.from(error).message)),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final selection = await showDialog<_AssignmentData>(
      context: context,
      builder: (context) => _AssignmentDialog(
        users: users,
        initialPrimaryUid: ticket.primaryAssigneeUid,
        initialParticipantUids: ticket.participantUids,
      ),
    );
    if (selection == null) return;
    await run(
      () => ref
          .read(maintenanceRepositoryProvider)!
          .assignTicket(
            ticketId: ticket.id,
            primaryAssigneeUid: selection.primaryUid,
            participantUids: selection.participantUids,
          ),
    );
  }

  Future<void> _escalate(BuildContext context, WidgetRef ref) async {
    final reason = await _askReason(
      context,
      title: 'ESCALAR URGENCIA',
      description:
          'Esta acción enviará una alerta urgente al personal de mantenimiento. Existe un tiempo de espera configurable entre alertas.',
      optional: true,
    );
    if (reason == null) return;
    await run(
      () => ref
          .read(maintenanceRepositoryProvider)!
          .escalateTicket(ticketId: ticket.id, reason: reason),
    );
  }

  Future<void> _changePriority(BuildContext context, WidgetRef ref) async {
    var selected = ticket.priority;
    final reasonController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Cambiar prioridad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TicketPriority>(
                initialValue: selected,
                items: TicketPriority.values
                    .map(
                      (priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) =>
                    setState(() => selected = value ?? selected),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo obligatorio',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (accepted != true) return;
    if (reason.length < 5) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Indique un motivo válido.')),
        );
      }
      return;
    }
    await run(
      () => ref
          .read(maintenanceRepositoryProvider)!
          .updatePriority(
            ticketId: ticket.id,
            priority: selected,
            reason: reason,
          ),
    );
  }

  Future<void> _updateProductionImpact(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final nextStopped = !ticket.productionStopped;
    final reason = await _askReason(
      context,
      title: nextStopped
          ? 'Reportar producción detenida'
          : 'Confirmar producción reanudada',
      description: nextStopped
          ? 'Se mostrará una alerta visible y se notificará a Mantenimiento.'
          : 'Se registrará la hora de reanudación en la trazabilidad.',
    );
    if (reason == null) return;
    await run(
      () => ref
          .read(maintenanceRepositoryProvider)!
          .updateProductionImpact(
            ticketId: ticket.id,
            productionStopped: nextStopped,
            reason: reason,
          ),
    );
  }

  static Future<String?> _askReason(
    BuildContext context, {
    required String title,
    String? description,
    bool optional = false,
  }) async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null) ...[
              Text(description),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: optional ? 'Motivo (opcional)' : 'Motivo *',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (accepted != true) return null;
    if (!optional && reason.length < 5) return null;
    return reason;
  }

  static IconData _targetIcon(TicketStatus target) => switch (target) {
    TicketStatus.acknowledged => Icons.mark_email_read_outlined,
    TicketStatus.assigned => Icons.assignment_ind_outlined,
    TicketStatus.inProgress => Icons.play_arrow_rounded,
    TicketStatus.waitingParts => Icons.inventory_2_outlined,
    TicketStatus.waitingExternal => Icons.local_shipping_outlined,
    TicketStatus.paused => Icons.pause_rounded,
    TicketStatus.resolved => Icons.task_alt_rounded,
    TicketStatus.closed => Icons.lock_outline_rounded,
    TicketStatus.cancelled => Icons.cancel_outlined,
    TicketStatus.pending => Icons.schedule_rounded,
  };

  static String _targetAction(TicketStatus target) => switch (target) {
    TicketStatus.acknowledged => 'Marcar recibido',
    TicketStatus.assigned => 'Asignar',
    TicketStatus.inProgress => 'Iniciar / reanudar',
    TicketStatus.waitingParts => 'Esperar repuesto',
    TicketStatus.waitingExternal => 'Espera externa',
    TicketStatus.paused => 'Pausar',
    TicketStatus.resolved => 'Resolver',
    TicketStatus.closed => 'Confirmar cierre',
    TicketStatus.cancelled => 'Cancelar',
    TicketStatus.pending => 'Pendiente',
  };
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({
    required this.users,
    required this.initialPrimaryUid,
    required this.initialParticipantUids,
  });

  final List<AppUser> users;
  final String? initialPrimaryUid;
  final List<String> initialParticipantUids;

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  String? _primaryUid;
  late final Set<String> _participantUids;

  @override
  void initState() {
    super.initState();
    final available = widget.users.map((user) => user.uid).toSet();
    _primaryUid = available.contains(widget.initialPrimaryUid)
        ? widget.initialPrimaryUid
        : null;
    _participantUids = widget.initialParticipantUids
        .where(available.contains)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Responsables del ticket'),
      content: SizedBox(
        width: 520,
        child: widget.users.isEmpty
            ? const Text('No hay técnicos activos disponibles.')
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _primaryUid,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Responsable principal *',
                      ),
                      items: widget.users
                          .map(
                            (technician) => DropdownMenuItem(
                              value: technician.uid,
                              child: Text(technician.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(() {
                        _primaryUid = value;
                        if (value != null) _participantUids.add(value);
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Participantes adicionales',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    ...widget.users.map(
                      (technician) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value:
                            technician.uid == _primaryUid ||
                            _participantUids.contains(technician.uid),
                        onChanged: technician.uid == _primaryUid
                            ? null
                            : (selected) => setState(() {
                                if (selected == true) {
                                  _participantUids.add(technician.uid);
                                } else {
                                  _participantUids.remove(technician.uid);
                                }
                              }),
                        title: Text(technician.name),
                        subtitle: Text(technician.email),
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
        FilledButton(
          onPressed: _primaryUid == null
              ? null
              : () => Navigator.pop(
                  context,
                  _AssignmentData(
                    primaryUid: _primaryUid!,
                    participantUids: _participantUids.toList(growable: false),
                  ),
                ),
          child: const Text('Guardar asignación'),
        ),
      ],
    );
  }
}

class _AssignmentData {
  const _AssignmentData({
    required this.primaryUid,
    required this.participantUids,
  });

  final String primaryUid;
  final List<String> participantUids;
}

class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog();

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final _key = GlobalKey<FormState>();
  final _diagnosis = TextEditingController();
  final _work = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _diagnosis.dispose();
    _work.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar resolución'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _key,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _requiredText(_diagnosis, 'Diagnóstico *'),
                const SizedBox(height: 12),
                _requiredText(_work, 'Trabajo realizado *'),
                const SizedBox(height: 12),
                _requiredText(_notes, 'Observaciones / solución *'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_key.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              _ResolutionData(
                diagnosis: _diagnosis.text.trim(),
                workPerformed: _work.text.trim(),
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Marcar resuelto'),
        ),
      ],
    );
  }

  static Widget _requiredText(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      minLines: 2,
      maxLines: 5,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      validator: (value) => (value?.trim().length ?? 0) < 5
          ? 'Incluya al menos 5 caracteres.'
          : null,
    );
  }
}

class _ResolutionData {
  const _ResolutionData({
    required this.diagnosis,
    required this.workPerformed,
    required this.notes,
  });

  final String diagnosis;
  final String workPerformed;
  final String notes;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LongData extends StatelessWidget {
  const _LongData({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

class _NoComments extends StatelessWidget {
  const _NoComments();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Todavía no hay comentarios. Inicie la conversación.'),
      ),
    );
  }
}

class _TicketNotFound extends StatelessWidget {
  const _TicketNotFound();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('El ticket no existe o fue retirado.')),
  );
}

class _TicketAccessDenied extends StatelessWidget {
  const _TicketAccessDenied();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('No tiene permiso para ver este ticket.')),
  );
}
