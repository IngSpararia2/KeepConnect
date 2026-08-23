import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/app.dart';
import 'app/app_providers.dart';
import 'core/database/database_service.dart';
import 'core/notifications/notification_service.dart';
import 'core/session/local_session.dart';
import 'features/maintenance/data/sqlite_maintenance_repository.dart';
import 'features/maintenance/application/form_template_providers.dart';
import 'features/maintenance/data/sqlite_form_template_repository.dart';
import 'features/organization/data/sqlite_organization_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO');
  Intl.defaultLocale = 'es_CO';

  final database = await DatabaseService.open();
  late LocalSession session;
  final organizationRepository = SqliteOrganizationRepository(
    database,
    context: () => session.accessContext,
  );
  session = await LocalSession.load(
    resolveUser: organizationRepository.findUser,
  );
  final notifications = LocalNotificationService();
  await notifications.initialize();
  final repository = SqliteMaintenanceRepository(
    database,
    notificationGateway: notifications,
    context: () => session.accessContext,
  );
  final formTemplateRepository = SqliteFormTemplateRepository(
    database,
    context: () => session.accessContext,
  );

  runApp(
    ProviderScope(
      overrides: [
        localSessionProvider.overrideWithValue(session),
        notificationServiceProvider.overrideWithValue(notifications),
        maintenanceRepositoryProvider.overrideWithValue(repository),
        organizationRepositoryProvider.overrideWithValue(
          organizationRepository,
        ),
        authenticationRepositoryProvider.overrideWithValue(
          organizationRepository,
        ),
        formTemplateRepositoryProvider.overrideWithValue(
          formTemplateRepository,
        ),
      ],
      child: const GestionInternaApp(),
    ),
  );
}
