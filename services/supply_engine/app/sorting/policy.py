"""
C4: Decision policy layer – determines ACCEPT/REJECT/UNCERTAIN for each surface.
C5: Gold promotion service – promotes eligible items to Gold tier.

Each decision is versioned and carries reason codes for auditability.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from app.sorting.classifier import ClassificationResult, CLASSIFICATION_VERSION


# ============================================================================
# C4: DECISION POLICY
# ============================================================================

POLICY_VERSION = 1

# Default thresholds – can be overridden per surface
DEFAULT_ACCEPT_THRESHOLD = 0.60   # Accept if top1_confidence >= this
DEFAULT_REJECT_THRESHOLD = 0.20   # Reject if top1_confidence <= this
DEFAULT_MIN_MARGIN = 0.10         # Minimum margin between top-1 and top-2
DEFAULT_MIN_COMPLETENESS = 0.40   # Minimum extraction completeness score
DEFAULT_REQUIRE_IMAGES = True     # Require at least one image


@dataclass
class SurfacePolicy:
    """Policy configuration for a deck surface (e.g., 'swiper_deck_sofas')."""
    surface_id: str
    allowed_categories: list[str]   # Categories that belong on this surface
    accept_threshold: float = DEFAULT_ACCEPT_THRESHOLD
    reject_threshold: float = DEFAULT_REJECT_THRESHOLD
    min_margin: float = DEFAULT_MIN_MARGIN
    min_completeness: float = DEFAULT_MIN_COMPLETENESS
    require_images: bool = DEFAULT_REQUIRE_IMAGES
    require_price: bool = True
    max_price: float | None = None  # Optional price ceiling
    min_price: float | None = None  # Optional price floor


# Pre-configured surfaces
SURFACE_POLICIES: dict[str, SurfacePolicy] = {
    "swiper_deck_sofas": SurfacePolicy(
        surface_id="swiper_deck_sofas",
        allowed_categories=["sofa", "corner_sofa", "bed_sofa"],
        accept_threshold=0.55,
        min_margin=0.10,
    ),
    "swiper_deck_all_furniture": SurfacePolicy(
        surface_id="swiper_deck_all_furniture",
        allowed_categories=list(set([
            "sofa", "corner_sofa", "bed_sofa", "armchair",
            "dining_table", "coffee_table", "bed", "chair",
            "rug", "lamp", "storage", "desk", "outdoor",
        ])),
        accept_threshold=0.45,
        min_margin=0.05,
    ),
}


@dataclass
class EligibilityDecision:
    """The output of a policy decision for a single item on a surface."""
    surface_id: str
    decision: str  # "ACCEPT", "REJECT", "UNCERTAIN"
    reason_codes: list[str]
    policy_version: int = POLICY_VERSION
    decided_at: str = ""
    classification_version: int = CLASSIFICATION_VERSION
    confidence: float = 0.0
    predicted_category: str = ""

    def __post_init__(self):
        if not self.decided_at:
            self.decided_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def evaluate_eligibility(
    *,
    classification: ClassificationResult,
    surface_id: str,
    completeness_score: float,
    has_images: bool,
    has_price: bool,
    price_amount: float | None = None,
    policy: SurfacePolicy | None = None,
) -> EligibilityDecision:
    """
    Evaluate whether an item is eligible for a given surface.

    Returns ACCEPT, REJECT, or UNCERTAIN with reason codes.

    Decision logic (C4):
    1. If category not in allowed_categories → REJECT
    2. If confidence >= accept_threshold AND margin >= min_margin → ACCEPT
    3. If confidence <= reject_threshold → REJECT
    4. Otherwise → UNCERTAIN (routed to review queue)
    """
    if policy is None:
        policy = SURFACE_POLICIES.get(surface_id)
        if policy is None:
            return EligibilityDecision(
                surface_id=surface_id,
                decision="REJECT",
                reason_codes=["unknown_surface"],
                predicted_category=classification.predicted_category,
                confidence=classification.top1_confidence,
            )

    reasons: list[str] = []
    cat = classification.predicted_category

    # Gate 1: Category must be allowed
    if cat not in policy.allowed_categories and cat != "unknown":
        return EligibilityDecision(
            surface_id=surface_id,
            decision="REJECT",
            reason_codes=[f"category_not_allowed:{cat}"],
            predicted_category=cat,
            confidence=classification.top1_confidence,
        )

    # Gate 2: Required fields
    if policy.require_images and not has_images:
        reasons.append("missing_images")
    if policy.require_price and not has_price:
        reasons.append("missing_price")
    if completeness_score < policy.min_completeness:
        reasons.append(f"low_completeness:{completeness_score:.2f}")

    # Gate 3: Price bounds
    if price_amount is not None:
        if policy.max_price and price_amount > policy.max_price:
            reasons.append(f"price_above_max:{price_amount}")
        if policy.min_price and price_amount < policy.min_price:
            reasons.append(f"price_below_min:{price_amount}")

    # If hard gates fail → REJECT
    if reasons:
        return EligibilityDecision(
            surface_id=surface_id,
            decision="REJECT",
            reason_codes=reasons,
            predicted_category=cat,
            confidence=classification.top1_confidence,
        )

    # Gate 4: Confidence thresholds
    conf = classification.top1_confidence
    margin = classification.top1_top2_margin

    if cat == "unknown":
        return EligibilityDecision(
            surface_id=surface_id,
            decision="UNCERTAIN",
            reason_codes=["unclassified"],
            predicted_category=cat,
            confidence=conf,
        )

    if conf >= policy.accept_threshold and margin >= policy.min_margin:
        return EligibilityDecision(
            surface_id=surface_id,
            decision="ACCEPT",
            reason_codes=["meets_thresholds"],
            predicted_category=cat,
            confidence=conf,
        )

    if conf <= policy.reject_threshold:
        return EligibilityDecision(
            surface_id=surface_id,
            decision="REJECT",
            reason_codes=[f"low_confidence:{conf:.2f}"],
            predicted_category=cat,
            confidence=conf,
        )

    # Between reject and accept thresholds → UNCERTAIN
    uncertain_reasons = []
    if conf < policy.accept_threshold:
        uncertain_reasons.append(f"below_accept_threshold:{conf:.2f}<{policy.accept_threshold}")
    if margin < policy.min_margin:
        uncertain_reasons.append(f"low_margin:{margin:.2f}<{policy.min_margin}")

    return EligibilityDecision(
        surface_id=surface_id,
        decision="UNCERTAIN",
        reason_codes=uncertain_reasons or ["borderline"],
        predicted_category=cat,
        confidence=conf,
    )


# ============================================================================
# C5: GOLD PROMOTION SERVICE
# ============================================================================

def promote_to_gold(
    *,
    item_id: str,
    item_data: dict,
    classification: ClassificationResult,
    decisions: dict[str, EligibilityDecision],
) -> dict:
    """
    Create a Gold-tier record from an item that has been classified and accepted.

    Returns the Gold document data to write to Firestore.
    The Gold collection is what the deck reads from (E1).
    """
    # Find surfaces where item was ACCEPTED
    accepted_surfaces = [
        sid for sid, dec in decisions.items()
        if dec.decision == "ACCEPT"
    ]

    gold_doc = {
        "itemId": item_id,
        "eligibleSurfaces": accepted_surfaces,
        "predictedCategory": classification.predicted_category,
        "categoryConfidence": classification.top1_confidence,
        "categoryProbabilities": classification.category_probabilities,
        "classificationVersion": classification.classification_version,
        "policyVersion": POLICY_VERSION,
        "decisions": {
            sid: {
                "decision": dec.decision,
                "reasonCodes": dec.reason_codes,
                "confidence": dec.confidence,
                "decidedAt": dec.decided_at,
            }
            for sid, dec in decisions.items()
        },
        "promotedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        # Copy essential fields from item for fast deck reads
        "title": item_data.get("title"),
        "brand": item_data.get("brand"),
        "priceAmount": item_data.get("priceAmount"),
        "priceCurrency": item_data.get("priceCurrency"),
        "images": item_data.get("images"),
        "canonicalUrl": item_data.get("canonicalUrl"),
        "sourceId": item_data.get("sourceId"),
        "outboundUrl": item_data.get("outboundUrl"),
        "material": item_data.get("material"),
        "colorFamily": item_data.get("colorFamily"),
        "sizeClass": item_data.get("sizeClass"),
        "newUsed": item_data.get("newUsed", "new"),
        "styleTags": item_data.get("styleTags", []),
        "productType": item_data.get("productType"),
        "availability": item_data.get("availabilityStatus"),
        "priceOriginal": item_data.get("priceOriginal"),
        "discountPct": item_data.get("discountPct"),
        "isActive": True,
    }

    return gold_doc


def classify_and_decide(
    *,
    item_id: str,
    item_data: dict,
    surface_ids: list[str] | None = None,
) -> dict:
    """
    Convenience function: classify an item and evaluate eligibility for all surfaces.

    Returns a dict with classification result, decisions per surface, and optional Gold doc.
    """
    from urllib.parse import urlparse

    title = item_data.get("title", "")
    breadcrumbs = item_data.get("breadcrumbs", [])
    url_path = ""
    try:
        url_path = urlparse(item_data.get("canonicalUrl", "")).path
    except Exception:
        pass

    from app.sorting.classifier import classify_item

    classification = classify_item(
        title=title,
        breadcrumbs=breadcrumbs,
        url_path=url_path,
        product_type=item_data.get("productType"),
        facets=item_data.get("facets", {}),
        description=item_data.get("descriptionShort"),
    )

    surfaces = surface_ids or list(SURFACE_POLICIES.keys())
    decisions: dict[str, EligibilityDecision] = {}
    for sid in surfaces:
        decisions[sid] = evaluate_eligibility(
            classification=classification,
            surface_id=sid,
            completeness_score=item_data.get("completenessScore", 0.5),
            has_images=bool(item_data.get("images")),
            has_price=item_data.get("priceAmount") is not None,
            price_amount=item_data.get("priceAmount"),
        )

    # Build Gold doc if accepted for at least one surface
    gold_doc = None
    if any(d.decision == "ACCEPT" for d in decisions.values()):
        gold_doc = promote_to_gold(
            item_id=item_id,
            item_data=item_data,
            classification=classification,
            decisions=decisions,
        )

    return {
        "classification": {
            "predictedCategory": classification.predicted_category,
            "categoryProbabilities": classification.category_probabilities,
            "top1Confidence": classification.top1_confidence,
            "top1Top2Margin": classification.top1_top2_margin,
            "classificationVersion": classification.classification_version,
            "evidence": classification.evidence,
        },
        "decisions": {
            sid: {
                "decision": d.decision,
                "reasonCodes": d.reason_codes,
                "confidence": d.confidence,
                "decidedAt": d.decided_at,
            }
            for sid, d in decisions.items()
        },
        "goldDoc": gold_doc,
    }
