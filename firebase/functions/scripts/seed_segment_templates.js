#!/usr/bin/env node
/**
 * Seed Segment Templates
 * 
 * Seeds the system-defined segment templates into Firestore.
 * These templates are used for the v1 Sweden launch.
 * 
 * Usage:
 *   node seed_segment_templates.js
 * 
 * Prerequisites:
 *   - GOOGLE_APPLICATION_CREDENTIALS env var set, OR
 *   - Running on GCP with default credentials
 */

const admin = require("firebase-admin");

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * System-defined segment templates for v1 Sweden launch.
 * Matches the templates defined in segments.ts
 */
const SEGMENT_TEMPLATES = [
  {
    id: "budget-modern",
    name: "Budget-conscious modern",
    isTemplate: true,
    styleTags: ["modern", "minimalist"],
    budgetMin: 0,
    budgetMax: 15000, // SEK
    sizeClasses: ["2-sits", "3-sits"],
    geoRegion: "SE",
    description: "Affordable modern furniture for style-conscious shoppers",
  },
  {
    id: "premium-scandinavian",
    name: "Premium Scandinavian",
    isTemplate: true,
    styleTags: ["scandinavian", "nordic", "hygge"],
    budgetMin: 15000,
    budgetMax: 50000, // SEK
    sizeClasses: ["2-sits", "3-sits", "soffa-med-divan"],
    geoRegion: "SE",
    description: "High-quality Scandinavian design for discerning buyers",
  },
  {
    id: "compact-urban",
    name: "Compact urban",
    isTemplate: true,
    styleTags: ["modern", "minimalist", "space-saving"],
    budgetMin: 5000,
    budgetMax: 25000, // SEK
    sizeClasses: ["2-sits", "fåtölj"],
    geoRegion: "SE",
    description: "Space-efficient solutions for city apartments",
  },
  {
    id: "family-friendly",
    name: "Family-friendly",
    isTemplate: true,
    styleTags: ["practical", "durable", "easy-clean"],
    budgetMin: 10000,
    budgetMax: 40000, // SEK
    sizeClasses: ["3-sits", "soffa-med-divan", "hörnsoffa"],
    geoRegion: "SE",
    description: "Durable, easy-to-clean options for families with children",
  },
  {
    id: "luxury-design",
    name: "Luxury design",
    isTemplate: true,
    styleTags: ["luxury", "designer", "premium"],
    budgetMin: 40000,
    budgetMax: null, // No upper limit
    sizeClasses: ["2-sits", "3-sits", "soffa-med-divan", "hörnsoffa", "modul-soffa"],
    geoRegion: "SE",
    description: "Top-tier designer furniture for luxury seekers",
  },
  {
    id: "all-sweden",
    name: "All Sweden",
    isTemplate: true,
    styleTags: [], // No style filter
    budgetMin: null, // No budget filter
    budgetMax: null,
    sizeClasses: [], // No size filter
    geoRegion: "SE",
    description: "All products available in Sweden (baseline segment)",
  },
];

async function seedSegmentTemplates() {
  console.log("Starting segment template seeding...\n");

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const template of SEGMENT_TEMPLATES) {
    const docRef = db.collection("segments").doc(template.id);
    
    // Check if already exists
    const existing = await docRef.get();
    if (existing.exists) {
      console.log(`  ⏭  Skipping "${template.name}" (already exists)`);
      continue;
    }

    batch.set(docRef, {
      ...template,
      retailerId: null, // System templates have no retailer
      createdAt: now,
      updatedAt: now,
    });

    console.log(`  ✓  Added "${template.name}"`);
  }

  await batch.commit();

  console.log("\n✅ Segment template seeding complete!");
  console.log(`   Total templates: ${SEGMENT_TEMPLATES.length}`);
}

// Run the seeder
seedSegmentTemplates()
  .then(() => {
    console.log("\nDone.");
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ Error seeding segment templates:", error);
    process.exit(1);
  });
