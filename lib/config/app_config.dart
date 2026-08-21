abstract final class AppConfig {
  static const appName = 'Gestión Interna';
  static const applicationId = 'com.samuelpararia.gestioninterna';
  static const credits =
      'App desarrollada por Ing. Samuel Parariá – Derechos Reservados';

  static const maintenanceModuleId = 'maintenance';
  static const productionDepartmentId = 'production';
  static const maintenanceDepartmentId = 'maintenance';

  static const functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );
  static const useFirebaseEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
  );
  static const emulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  static const demoProjectId = 'demo-gestion-interna';

  static const maxPhotosPerTicket = 5;
  static const maxPhotoBytes = 5 * 1024 * 1024;
  static const ticketPageSize = 100;
}
