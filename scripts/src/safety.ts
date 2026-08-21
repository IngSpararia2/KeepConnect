import { applicationDefault, getApps, initializeApp, type App } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

export interface ParsedArguments {
  flags: Set<string>;
  values: Map<string, string>;
}

export interface AdminContext {
  app: App;
  auth: Auth;
  db: Firestore;
  args: ParsedArguments;
  projectId: string;
  production: boolean;
  dryRun: boolean;
}

export function parseArguments(argv = process.argv.slice(2)): ParsedArguments {
  const flags = new Set<string>();
  const values = new Map<string, string>();
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--") continue;
    if (!argument?.startsWith("--")) {
      throw new Error(`Argumento inesperado: ${argument ?? ""}`);
    }
    const withoutPrefix = argument.slice(2);
    const equalsAt = withoutPrefix.indexOf("=");
    if (equalsAt >= 0) {
      values.set(withoutPrefix.slice(0, equalsAt), withoutPrefix.slice(equalsAt + 1));
      continue;
    }
    const next = argv[index + 1];
    if (next && !next.startsWith("--")) {
      values.set(withoutPrefix, next);
      index += 1;
    } else {
      flags.add(withoutPrefix);
    }
  }
  return { flags, values };
}

export function requiredArgument(args: ParsedArguments, key: string): string {
  const value = args.values.get(key)?.trim();
  if (!value) throw new Error(`Falta el argumento obligatorio --${key}.`);
  return value;
}

function configureEmulators(projectId: string): void {
  process.env.GCLOUD_PROJECT = projectId;
  process.env.GOOGLE_CLOUD_PROJECT = projectId;
  process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
  process.env.FIREBASE_AUTH_EMULATOR_HOST ||= "127.0.0.1:9099";
  process.env.FIREBASE_STORAGE_EMULATOR_HOST ||= "127.0.0.1:9199";
}

export function initializeAdminContext(): AdminContext {
  const args = parseArguments();
  const production = args.flags.has("production");
  const dryRun = args.flags.has("dry-run");
  let projectId: string;

  if (production) {
    projectId = requiredArgument(args, "project");
    const confirmedProject = requiredArgument(args, "confirm-project");
    if (projectId !== confirmedProject) {
      throw new Error("--confirm-project debe coincidir exactamente con --project.");
    }
    if (projectId.startsWith("demo-") || projectId === "REPLACE_WITH_FIREBASE_PROJECT_ID") {
      throw new Error("El identificador indicado no parece un proyecto Firebase real.");
    }
    if (
      process.env.FIRESTORE_EMULATOR_HOST ||
      process.env.FIREBASE_AUTH_EMULATOR_HOST ||
      process.env.FIREBASE_STORAGE_EMULATOR_HOST
    ) {
      throw new Error(
        "Hay variables de Emulator activas. Elimínalas antes de ejecutar con --production."
      );
    }
  } else {
    projectId = args.values.get("project")?.trim() || "demo-gestion-interna";
    if (!projectId.startsWith("demo-")) {
      throw new Error(
        "Sin --production solo se aceptan project IDs que comiencen por demo-."
      );
    }
    configureEmulators(projectId);
  }

  const app = getApps()[0] ?? initializeApp(
    production
      ? {
          projectId,
          credential: applicationDefault(),
          storageBucket: `${projectId}.appspot.com`
        }
      : { projectId, storageBucket: `${projectId}.appspot.com` }
  );
  const mode = production ? "PRODUCCIÓN REAL" : "EMULADORES LOCALES";
  process.stdout.write(`\nModo: ${mode}\nProyecto: ${projectId}\nDry run: ${dryRun}\n\n`);
  return {
    app,
    auth: getAuth(app),
    db: getFirestore(app),
    args,
    projectId,
    production,
    dryRun
  };
}
