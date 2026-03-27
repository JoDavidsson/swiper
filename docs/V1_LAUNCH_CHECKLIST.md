# Swiper v1 Launch Checklist

> **Status:** DRAFT — Not reviewed  
> **Author:** CEO (executed by Mugen)  
> **Date:** 2026-03-27  
> **Repo:** https://github.com/JoDavidsson/swiper

---

## Purpose

This document is the explicit go/no-go gate for announcing "Swiper is live" to retailers. It exists because "MVP shipped" and "ready to invoice retailers" are very different states. Complete every item before the first retailer goes live.

---

## Go/No-Go Gates

For each section below: ✅ = complete, ⚠️ = in progress, ❌ = not started, 🚫 = blocked

---

### Section 1: Retailer Console v1 (Phase 13)

| # | Item | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 1.1 | Insights Feed — actionable "what to do today" cards | 🚫 | ? | Core value prop. Without this, retailers have no reason to log in. |
| 1.2 | Campaign Builder — segment + products + budget + schedule | 🚫 | ? | Retailers must be able to self-serve a campaign. |
| 1.3 | Confidence Score UI — per-product scores with reason codes | 🚫 | ? | Green/yellow/red banding + data volume indicator. |
| 1.4 | Catalog control — include/exclude SKUs, preview as card | 🚫 | ? | Retailer must be able to control which SKUs appear. |
| 1.5 | Trends module — Sweden → region → city → postcode tiers | 🚫 | ? | Location-based targeting is a key differentiator. |
| 1.6 | Campaign reporting — Confidence Score outcomes, not vanity metrics | 🚫 | ? | Must show CPScore (Cost per Confidence Score outcome). |
| 1.7 | Retailer onboarding flow — claim store, verify ownership | 🚫 | ? | How does a new retailer get started? |

**Section 1 owner:** Needs engineering assignment before any launch.

---

### Section 2: Real Retailer Supply

| # | Item | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 2.1 | At least 1 signed pilot agreement with a real Swedish retailer | 🚫 | Johannes (commercial) | Retailer must have live products we can feature. |
| 2.2 | At least 1 live product feed ingested into Firestore | 🚫 | Supply Engineer | Demo/sample data does NOT count. |
| 2.3 | Crawl validated on pilot retailer site (≥80% extraction success) | 🚫 | Supply Engineer | From crawl validation tests: Mio works. IKEA SE and Comfort are blocked by Cloudflare. |
| 2.4 | Retailer branding verified — images, logos, product data | 🚫 | Supply Engineer | Quality bar: images render correctly, prices are accurate. |
| 2.5 | Retailer account activated in system | 🚫 | ? | Retailer can log in and see their catalog. |

**Section 2 owner:** Commercial (2.1 Johannes) + Supply Engineer (2.2–2.5).

---

### Section 3: Admin Governance (Phase 14)

| # | Item | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 3.1 | Frequency cap controls — max 1-in-12 (configurable) | 🚫 | ? | Must be adjustable without a code deploy. |
| 3.2 | Relevance threshold controls — minimum match score to show featured | 🚫 | ? | Prevents irrelevant featured products. |
| 3.3 | Pacing controls — budget distribution over time | 🚫 | ? | Prevents budget burn-through. |
| 3.4 | Brand safety overrides — instant pause/exclude | 🚫 | ? | Must be fast (same day or faster). |
| 3.5 | Segment definition UI — create/edit targeting personas | 🚫 | ? | Style + budget + size + geo targeting. |

**Section 3 owner:** Needs engineering assignment.

---

### Section 4: Consumer Validation

| # | Item | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 4.1 | Beta users recruited — 50–100 real Swedish users | 🚫 | Johannes (commercial) | Friends, family, early testers. Not a public launch. |
| 4.2 | Analytics verified — all consumer events firing correctly | 🚫 | ? | Check: impression, swipe, like, share, decision_room_create, vote, outbound_click. |
| 4.3 | Funnel analysis — where do users drop off? | 🚫 | ? | Target: deck completion rate ≥50%, outbound CTR ≥5%. |
| 4.4 | Decision Room test — shared shortlist generates engagement | 🚫 | ? | Target: participation rate ≥30% (rooms with ≥2 participants). |
| 4.5 | Push notifications deferred or implemented | ⚠️ | ? | Phase 9.10 is marked Deferred. Decide: launch without it? |

**Section 4 owner:** Product + Johannes.

---

### Section 5: Commercial & Legal

| # | Item | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 5.1 | Pricing finalized — pilot pricing document exists | 🚫 | Johannes (commercial) | Must have price list before first invoice. |
| 5.2 | Pilot agreement template drafted | 🚫 | Johannes (commercial) | Legal template for first retailer pilots. |
| 5.3 | GDPR/privacy review (lawyer or self-audit) | 🚫 | Johannes (commercial) | Swedish DPA has strong enforcement. |
| 5.4 | Cookie consent handling for web app | 🚫 | ? | Required before any marketing/smoke-traffic. |
| 5.5 | Terms of service / privacy policy published | 🚫 | Johannes (commercial) | Required for App Store / Google Play. |

**Section 5 owner:** Johannes (commercial).

---

### Section 6: Technical Launch Readiness

| # | Item | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 6.1 | Staging environment deployed and smoke tests passing | 🚫 | ? | All Section 7 smoke tests must pass on staging. |
| 6.2 | Production Firebase project configured | 🚫 | ? | Separate from emulators/sample data. |
| 6.3 | Domain and SSL configured (swiperapp.com or equivalent) | 🚫 | Johannes (commercial) | Needed for retailer console and App Store. |
| 6.4 | App Store / Google Play listing drafted | 🚫 | Johannes (commercial) | Not live yet, but ready to publish. |
| 6.5 | Error monitoring active (e.g. Sentry) | 🚫 | ? | Must know when the app breaks in production. |

**Section 6 owner:** Engineering + Johannes.

---

### Section 7: Smoke Tests (Automated)

Run these on staging before any launch announcement.

```
Smoke test suite: tests/v1_smoke_tests/
Status: NOT YET WRITTEN
```

| # | Test | Expected Result |
|---|------|-----------------|
| 7.1 | App deck loads with ≥1 real product | HTTP 200, non-empty item list |
| 7.2 | Swipe right → item appears in likes | Item ID in likes list |
| 7.3 | Share shortlist → public URL returns room data | HTTP 200, room token valid |
| 7.4 | Decision Room → submit vote | Vote recorded in Firestore |
| 7.5 | Featured product card shows "Featured" label | Featured badge visible |
| 7.6 | Outbound redirect fires with correct UTM params | Click logged + redirect to retailer URL |
| 7.7 | Admin: trigger ingestion → items appear in Firestore | Item count increases |
| 7.8 | Confidence Score calculated for test product | Score 0–100 with reason code |
| 7.9 | Retailer console: Insights Feed loads | At least 1 insight card visible |
| 7.10 | Campaign creation → featured slot appears in deck | Featured label on correct item |

---

## Sign-Off

This document must be reviewed and signed by the CEO before any launch announcement.

| Role | Name | Date | Signature |
|------|------|------|-----------|
| CEO | Johannes Davidsson | TBD | |
| Engineering Lead | | | |
| Commercial/BD | | | |

---

## Notes

### Crawl Validation Results (2026-03-27)

From live testing against Swedish furniture retailers:

| Retailer | Status | Notes |
|----------|--------|-------|
| Mio | ✅ Works | 4,002 products via sitemap. Best first pilot candidate. |
| Svenska Hem | ⚠️ Partial | Low product volume via sitemap. May need crawl fallback. |
| Comfort | ❌ Blocked | Cloudflare blocks sitemap. SPA site. Wrong category (VVS, not furniture). |
| Skona Hem | ❌ Wrong domain | Domain now editorial. Not an active e-commerce site. |
| IKEA SE | ❌ Blocked | Cloudflare blocks all. Requires Playwright/browser fallback. |

**Recommendation:** Start with Mio as first pilot. They have clean sitemaps, large catalog, and straightforward JSON-LD.

### Golden Card v2 Rollout State

- **Current:** 100% rollout (all new users get GCv2)
- **Kill switch:** `ENABLE_GOLDEN_CARD_V2=false` or `GOLDEN_CARD_V2_ROLLOUT_PERCENT=0`
- **Legacy fallback:** `ENABLE_LEGACY_GOLD_CARD=true`
- **Rollout plan:** 10% → 50% → 100% with observability gates (defined in `RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md`)

### Critical Unknowns

These must be resolved before Section 5 sign-off:

1. **What do we charge?** CPScore pricing model not yet costed. What is the unit economics?
2. **How fast can we sign a retailer?** Legal review of pilot agreement template.
3. **What's the minimum viable catalog size?** If Mio has 4,000 products, do we need all of them?
4. **Who manages the retailer relationship?** CSM, account manager, or self-serve?
