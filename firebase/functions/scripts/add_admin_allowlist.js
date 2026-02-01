#!/usr/bin/env node
/**
 * Add an admin email to Firestore adminAllowlist (document ID = email).
 * Prereqs: GOOGLE_APPLICATION_CREDENTIALS set to service account JSON path.
 * For emulator: set FIRESTORE_EMULATOR_HOST=localhost:8180 (or your port).
 *
 * Usage: node scripts/add_admin_allowlist.js <email>
 * Example: node scripts/add_admin_allowlist.js admin@example.com
 */
const admin = require("firebase-admin");

const email = process.argv[2];
if (!email || !email.includes("@")) {
  console.error("Usage: node scripts/add_admin_allowlist.js <email>");
  console.error("Example: node scripts/add_admin_allowlist.js you@example.com");
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.applicationDefault() });
}

const db = admin.firestore();

db.collection("adminAllowlist")
  .doc(email.trim())
  .set({ addedAt: admin.firestore.FieldValue.serverTimestamp() })
  .then(() => {
    console.log("Added to adminAllowlist:", email.trim());
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
