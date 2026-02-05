#!/usr/bin/env node
/**
 * Seed curatedOnboardingSofas collection with 6 sample items.
 * 
 * Usage:
 *   node seed_curated_sofas.js
 * 
 * This script will:
 * 1. Query the items collection to find 6 items with images
 * 2. Add them to the curatedOnboardingSofas collection with order
 * 
 * Set GOOGLE_APPLICATION_CREDENTIALS or run against emulator with FIRESTORE_EMULATOR_HOST.
 */

const admin = require("firebase-admin");

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || "swiper-app",
  });
}

const db = admin.firestore();

async function seedCuratedSofas() {
  console.log("Seeding curatedOnboardingSofas collection...");

  // Check if already seeded
  const existingSnap = await db.collection("curatedOnboardingSofas").limit(1).get();
  if (!existingSnap.empty) {
    console.log("curatedOnboardingSofas already has items. Skipping seed.");
    console.log("To re-seed, delete the existing items first.");
    return;
  }

  // Find 6 items with images to use as curated sofas
  const itemsSnap = await db
    .collection("items")
    .limit(20)
    .get();

  if (itemsSnap.empty) {
    console.log("No items found in the items collection. Please run the item ingestion first.");
    return;
  }

  // Filter for items with valid images
  const itemsWithImages = itemsSnap.docs
    .filter((doc) => {
      const data = doc.data();
      const images = data.images || [];
      return Array.isArray(images) && images.length > 0 && images[0]?.url;
    })
    .slice(0, 6);

  if (itemsWithImages.length < 6) {
    console.log(`Warning: Only found ${itemsWithImages.length} items with images (wanted 6).`);
    if (itemsWithImages.length === 0) {
      console.log("Cannot seed without any items with images.");
      return;
    }
  }

  // Add to curatedOnboardingSofas
  const batch = db.batch();
  
  itemsWithImages.forEach((doc, index) => {
    const ref = db.collection("curatedOnboardingSofas").doc(doc.id);
    batch.set(ref, {
      order: index,
      addedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`  Adding item ${index + 1}: ${doc.id} (${doc.data().title || "Untitled"})`);
  });

  await batch.commit();
  console.log(`\nSuccessfully seeded ${itemsWithImages.length} curated sofas.`);
}

seedCuratedSofas()
  .then(() => {
    console.log("Done.");
    process.exit(0);
  })
  .catch((err) => {
    console.error("Error seeding curated sofas:", err);
    process.exit(1);
  });
