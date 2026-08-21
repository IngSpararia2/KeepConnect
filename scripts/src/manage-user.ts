import { Timestamp } from "firebase-admin/firestore";

import {
  initializeAdminContext,
  requiredArgument,
  type AdminContext
} from "./safety.js";

const VALID_ROLES = new Set(["admin", "production", "maintenance"]);
const context = initializeAdminContext();

async function findUid(admin: AdminContext): Promise<string> {
  const uid = admin.args.values.get("uid")?.trim();
  if (uid) return uid;
  const email = requiredArgument(admin.args, "email").toLowerCase();
  return (await admin.auth.getUserByEmail(email)).uid;
}

async function disableDevices(uid: string): Promise<void> {
  const devices = await context.db.collection(`users/${uid}/devices`).get();
  if (devices.empty) return;
  const batch = context.db.batch();
  devices.docs.forEach((device) =>
    batch.set(
      device.ref,
      {
        notificationsEnabled: false,
        permissionStatus: "disabledByAdministrator",
        updatedAt: Timestamp.now()
      },
      { merge: true }
    )
  );
  await batch.commit();
}

async function upsertUser(): Promise<void> {
  const email = requiredArgument(context.args, "email").toLowerCase();
  const name = requiredArgument(context.args, "name");
  const role = requiredArgument(context.args, "role");
  const departmentId = requiredArgument(context.args, "department");
  if (!VALID_ROLES.has(role)) {
    throw new Error("--role debe ser admin, production o maintenance.");
  }
  const department = await context.db.doc(`departments/${departmentId}`).get();
  if (!department.exists || department.data()?.active !== true) {
    throw new Error(`El área ${departmentId} no existe o está inactiva. Ejecuta primero el seed.`);
  }

  let existing;
  try {
    existing = await context.auth.getUserByEmail(email);
  } catch (error: unknown) {
    const code =
      typeof error === "object" && error !== null && "code" in error
        ? String((error as { code: unknown }).code)
        : "";
    if (code !== "auth/user-not-found") throw error;
  }

  if (context.dryRun) {
    process.stdout.write(
      `${existing ? "Actualizaría" : "Crearía"} ${email}, rol ${role}, área ${departmentId}.\n`
    );
    return;
  }

  let uid: string;
  if (existing) {
    uid = existing.uid;
    await context.auth.updateUser(uid, { displayName: name, disabled: false });
  } else {
    const passwordEnvironmentName = requiredArgument(context.args, "password-env");
    if (!/^[A-Z][A-Z0-9_]{2,80}$/.test(passwordEnvironmentName)) {
      throw new Error("--password-env debe ser el nombre de una variable de entorno en mayúsculas.");
    }
    const password = process.env[passwordEnvironmentName];
    if (!password || password.length < 8) {
      throw new Error(
        `La variable ${passwordEnvironmentName} debe contener una contraseña de al menos 8 caracteres.`
      );
    }
    const created = await context.auth.createUser({ email, password, displayName: name });
    uid = created.uid;
  }

  const now = Timestamp.now();
  const userRef = context.db.doc(`users/${uid}`);
  const oldProfile = await userRef.get();
  await userRef.set(
    {
      uid,
      name,
      email,
      role,
      departmentId,
      active: true,
      createdAt: oldProfile.data()?.createdAt ?? now,
      updatedAt: now
    },
    { merge: true }
  );
  process.stdout.write(`Usuario listo: ${email} (${uid}), rol ${role}, área ${departmentId}.\n`);
}

async function changeActivation(active: boolean): Promise<void> {
  const uid = await findUid(context);
  const user = await context.auth.getUser(uid);
  if (context.dryRun) {
    process.stdout.write(`${active ? "Activaría" : "Desactivaría"} ${user.email ?? uid}.\n`);
    return;
  }
  await context.auth.updateUser(uid, { disabled: !active });
  if (!active) await context.auth.revokeRefreshTokens(uid);
  await context.db.doc(`users/${uid}`).set(
    { active, updatedAt: Timestamp.now() },
    { merge: true }
  );
  if (!active) await disableDevices(uid);
  process.stdout.write(`${active ? "Activado" : "Desactivado"}: ${user.email ?? uid}.\n`);
}

async function main(): Promise<void> {
  const action = context.args.values.get("action") ?? "upsert";
  switch (action) {
    case "upsert":
      await upsertUser();
      break;
    case "activate":
      await changeActivation(true);
      break;
    case "deactivate":
      await changeActivation(false);
      break;
    default:
      throw new Error("--action debe ser upsert, activate o deactivate.");
  }
}

main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
