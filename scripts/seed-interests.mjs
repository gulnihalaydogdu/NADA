/**
 * Seed Firestore `interests` from firebase/interests.seed.json
 *
 * Usage (from repo root):
 *   npm install
 *   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/serviceAccount.json"
 *   npm run seed:interests
 *
 *   # Or after `gcloud auth application-default login`:
 *   export GCLOUD_PROJECT=nada-app-33
 *   npm run seed:interests
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { applicationDefault, cert, getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const seedPath = join(root, "firebase", "interests.seed.json");
const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "nada-app-33";

function initAdmin() {
  if (getApps().length) return;

  const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (keyPath) {
    const serviceAccount = JSON.parse(readFileSync(keyPath, "utf8"));
    initializeApp({
      credential: cert(serviceAccount),
      projectId: serviceAccount.project_id || projectId,
    });
    return;
  }

  initializeApp({
    credential: applicationDefault(),
    projectId,
  });
}

async function main() {
  const raw = JSON.parse(readFileSync(seedPath, "utf8"));
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new Error(`No interests in ${seedPath}`);
  }

  initAdmin();
  const db = getFirestore();
  const batchSize = 400;
  let written = 0;

  for (let i = 0; i < raw.length; i += batchSize) {
    const chunk = raw.slice(i, i + batchSize);
    const batch = db.batch();

    for (const item of chunk) {
      const { id, label, category, isActive, sortOrder, locale } = item;
      if (!id || !label) {
        throw new Error(`Invalid seed row: ${JSON.stringify(item)}`);
      }
      const ref = db.collection("interests").doc(id);
      batch.set(
        ref,
        {
          label,
          category,
          isActive: Boolean(isActive),
          sortOrder: Number(sortOrder) || 0,
          locale: locale || "en",
        },
        { merge: true }
      );
    }

    await batch.commit();
    written += chunk.length;
  }

  console.log(`Seeded ${written} interests into ${projectId}/interests (merge).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
