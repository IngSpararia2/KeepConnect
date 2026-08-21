import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../core/utils/date_time_formatters.dart';
import '../application/maintenance_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(notificationsProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('No hay notificaciones para esta vista.'),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = items[index];
                  return Card(
                    color: item.read
                        ? null
                        : Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: .35),
                    child: ListTile(
                      leading: Icon(
                        item.read
                            ? Icons.notifications_none
                            : Icons.notifications_active,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: item.read
                              ? FontWeight.w600
                              : FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        '${item.message}\n${AppDateTime.dateTime(item.createdAt)}',
                      ),
                      isThreeLine: true,
                      onTap: () async {
                        await ref
                            .read(maintenanceRepositoryProvider)
                            .markNotificationRead(item.id);
                        if (context.mounted) {
                          context.push('/tickets/${item.ticketId}');
                        }
                      },
                    ),
                  );
                },
              ),
      );
}
