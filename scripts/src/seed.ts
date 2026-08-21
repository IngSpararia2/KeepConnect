import { Timestamp } from "firebase-admin/firestore";

import { initializeAdminContext } from "./safety.js";

const context = initializeAdminContext();
const now = Timestamp.now();

const categories = [
  ["repair", "Reparación"],
  ["corrective-maintenance", "Mantenimiento correctivo"],
  ["preventive-maintenance", "Mantenimiento preventivo"],
  ["installation", "Instalación"],
  ["modification", "Modificación"],
  ["infrastructure", "Infraestructura"],
  ["electricity", "Electricidad"],
  ["plumbing", "Agua/fontanería"],
  ["production-equipment", "Equipos de producción"],
  ["tools", "Herramientas"],
  ["furniture", "Mobiliario"],
  ["safety", "Seguridad"],
  ["other", "Otro"]
] as const;

const documents: Array<[string, Record<string, unknown>]> = [
  [
    "departments/production",
    {
      code: "PROD",
      name: "Planta de Producción",
      active: true,
      createdAt: now,
      updatedAt: now
    }
  ],
  [
    "departments/maintenance",
    {
      code: "MTTO",
      name: "Mantenimiento",
      active: true,
      createdAt: now,
      updatedAt: now
    }
  ],
  [
    "modules/maintenance",
    {
      code: "maintenance",
      name: "Mantenimiento",
      sourceDepartmentIds: ["production"],
      destinationDepartmentIds: ["maintenance"],
      active: true,
      iconKey: "build",
      formTemplateId: "maintenance-v1",
      sortOrder: 10,
      createdAt: now,
      updatedAt: now
    }
  ],
  [
    "assets/columbia-21",
    {
      code: "COL-21",
      name: "Columbia 21",
      normalizedName: "columbia 21",
      departmentId: "production",
      location: "Planta de Producción",
      critical: true,
      active: true,
      createdAt: now,
      updatedAt: now
    }
  ],
  [
    "assets/compressor",
    {
      code: "COMP-01",
      name: "Compresor",
      normalizedName: "compresor",
      departmentId: "production",
      location: "Servicios industriales",
      critical: false,
      active: true,
      createdAt: now,
      updatedAt: now
    }
  ],
  [
    "assets/infrastructure",
    {
      code: "INFRA",
      name: "Infraestructura",
      normalizedName: "infraestructura",
      departmentId: "production",
      location: "Instalaciones generales",
      critical: false,
      active: true,
      createdAt: now,
      updatedAt: now
    }
  ],
  [
    "form_templates/maintenance-v1",
    {
      moduleId: "maintenance",
      name: "Solicitud de mantenimiento",
      version: 1,
      schemaVersion: 1,
      active: true,
      fields: [
        {
          id: "symptom",
          type: "shortText",
          label: "Síntoma principal",
          required: true,
          order: 10
        },
        {
          id: "observedDetails",
          type: "longText",
          label: "Detalles adicionales observados",
          required: false,
          order: 20
        },
        {
          id: "affectedUnits",
          type: "number",
          label: "Unidades afectadas",
          required: false,
          validation: { minimum: 0, maximum: 100000 },
          order: 30
        },
        {
          id: "intermittent",
          type: "yesNo",
          label: "¿La falla es intermitente?",
          required: true,
          order: 40
        },
        {
          id: "shift",
          type: "singleChoice",
          label: "Turno en el que ocurrió",
          required: false,
          options: ["Mañana", "Tarde", "Noche"],
          order: 50
        },
        {
          id: "observedSignals",
          type: "multipleChoice",
          label: "Señales observadas",
          required: false,
          options: ["Ruido", "Vibración", "Olor", "Calor", "Fuga"],
          order: 60
        },
        {
          id: "safeShutdown",
          type: "checklist",
          label: "Acciones de seguridad realizadas",
          required: false,
          options: ["Equipo detenido", "Energía aislada", "Área señalizada"],
          order: 70
        },
        {
          id: "firstObservedAt",
          type: "date",
          label: "Fecha en que se observó por primera vez",
          required: false,
          order: 80
        }
      ],
      createdAt: now,
      updatedAt: now
    }
  ],
  [
    "settings/maintenance",
    {
      automaticEscalationEnabled: true,
      criticalAcknowledgementMinutes: 30,
      highAcknowledgementMinutes: 120,
      manualEscalationCooldownMinutes: 15,
      automaticEscalationRepeatMinutes: 30,
      maximumAutomaticEscalationLevel: 3,
      maxPhotosPerTicket: 5,
      maxPhotoBytes: 5242880,
      normalNotificationChannelId: "gestion_interna_normal_v1",
      urgentNotificationChannelId: "gestion_interna_urgent_v1",
      priorityPolicy: {
        version: "demo-v1",
        productionStoppedWeight: 5,
        safetyRiskWeight: 7,
        criticalAssetWeight: 2,
        moderateImpactWeight: 1,
        severeImpactWeight: 2,
        moderateImpactFromPercentage: 25,
        severeImpactFromPercentage: 75,
        mediumThreshold: 2,
        highThreshold: 5,
        criticalThreshold: 7,
        safetyRiskMinimumPriority: "critical",
        stoppedCriticalAssetMinimumPriority: "critical"
      },
      updatedAt: now
    }
  ]
];

categories.forEach(([id, name], index) => {
  documents.push([
    `ticket_categories/${id}`,
    {
      moduleId: "maintenance",
      name,
      normalizedName: name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase(),
      active: true,
      sortOrder: (index + 1) * 10,
      createdAt: now,
      updatedAt: now
    }
  ]);
});

async function main(): Promise<void> {
  if (context.dryRun) {
    process.stdout.write(`Se escribirían ${documents.length} documentos:\n`);
    documents.forEach(([path]) => process.stdout.write(`- ${path}\n`));
    return;
  }
  const batch = context.db.batch();
  documents.forEach(([path, data]) => batch.set(context.db.doc(path), data, { merge: true }));
  await batch.commit();
  process.stdout.write(`Seed completado: ${documents.length} documentos creados/actualizados.\n`);
  process.stdout.write("No se crearon usuarios ni contraseñas. Usa manage-user por separado.\n");
}

main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
