"""
C1: Generic category classification (replaces sofa-only confidence).
C2: Feature builder with evidence provenance.
C3: Rule scorer with positive/negative taxonomy lexicons.

Classifies items into furniture categories using breadcrumbs, title, URL path,
and facets as evidence. Each classification carries confidence, evidence trail,
and version for reprocessing.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


# ============================================================================
# C1: CATEGORY TAXONOMY
# ============================================================================

# Generic furniture taxonomy – each category has positive and negative lexicons.
# Positive tokens boost the category score; negative tokens suppress it.
# Both Swedish and English keywords included for Swedish retailer coverage.
CATEGORY_LEXICONS: dict[str, dict[str, list[str]]] = {
    "sofa": {
        "positive": [
            "soffa", "soffor", "sofa", "sofas", "couch",
            "divansoffa", "hörnsoffa", "modulsoffa", "u-soffa",
            "3-sits", "2-sits", "4-sits",
        ],
        "negative": ["soffbord", "soffkudde", "sofftäcke", "sofa table", "sofa cushion"],
    },
    "armchair": {
        "positive": ["fåtölj", "fåtöljer", "armchair", "armchairs", "karmstol", "öronlappsfåtölj", "snurrstol"],
        "negative": [],
    },
    "bed_sofa": {
        "positive": ["bäddsoffa", "bäddsoffor", "sleeper sofa", "sofa bed", "sov-soffa"],
        "negative": [],
    },
    "corner_sofa": {
        "positive": ["hörnsoffa", "hörnsoffor", "corner sofa", "divansoffa", "l-soffa", "u-soffa"],
        "negative": [],
    },
    "dining_table": {
        "positive": ["matbord", "dining table", "köksbord"],
        "negative": ["matbordslampa", "matbordsstol"],
    },
    "coffee_table": {
        "positive": ["soffbord", "coffee table", "vardagsrumsbord"],
        "negative": [],
    },
    "bed": {
        "positive": ["säng", "sängar", "bed", "beds", "ramsäng", "kontinentalsäng"],
        "negative": ["bäddset", "sängkläder", "sängbord", "bedside", "bed frame"],
    },
    "chair": {
        "positive": ["stol", "stolar", "chair", "chairs", "matstol", "pinnstol", "barstol"],
        "negative": ["stolsdyna"],
    },
    "rug": {
        "positive": ["matta", "mattor", "rug", "rugs", "carpet"],
        "negative": [],
    },
    "lamp": {
        "positive": ["lampa", "lampor", "lamp", "light", "lighting", "taklampa", "bordslampa", "golvlampa"],
        "negative": [],
    },
    "storage": {
        "positive": ["förvaring", "byrå", "skänk", "sideboard", "bokhylla", "hyllsystem", "tv-bänk", "vitrinskåp"],
        "negative": [],
    },
    "desk": {
        "positive": ["skrivbord", "desk", "kontorsbord", "arbetsbord"],
        "negative": [],
    },
    "outdoor": {
        "positive": ["utomhus", "outdoor", "trädgård", "balkong", "utesoffa", "utemöbel"],
        "negative": [],
    },
    "decor": {
        "positive": ["inredning", "dekoration", "decor", "vas", "ljusstake", "spegel", "tavla", "konst"],
        "negative": [],
    },
    "textile": {
        "positive": ["textil", "kudde", "pläd", "gardin", "curtain", "cushion", "throw"],
        "negative": [],
    },
}

CLASSIFICATION_VERSION = 1


@dataclass
class CategoryEvidence:
    """A single piece of evidence for a classification."""
    source: str  # "breadcrumb", "title", "url_path", "facet", "jsonld_type"
    snippet: str  # The actual text that matched
    matched_tokens: list[str]  # Which lexicon tokens matched
    weight: float = 1.0  # How much this evidence contributes


@dataclass
class ClassificationResult:
    """Output of the category classifier (C1)."""
    predicted_category: str  # Top-1 predicted category
    category_probabilities: dict[str, float]  # Top-N probabilities
    top1_confidence: float  # Confidence of top prediction (0.0-1.0)
    top1_top2_margin: float  # Gap between top-1 and top-2
    classification_version: int = CLASSIFICATION_VERSION
    evidence: list[dict] = field(default_factory=list)  # Serializable evidence trail


# ============================================================================
# C2: FEATURE BUILDER
# ============================================================================

def _build_features(
    *,
    title: str,
    breadcrumbs: list[str],
    url_path: str,
    product_type: str | None,
    facets: dict[str, str],
    description: str | None,
) -> list[CategoryEvidence]:
    """
    Build evidence features from all available signals.

    Each feature is a CategoryEvidence with source, snippet, and matched tokens.
    Evidence provenance is tracked for explainability (C2).
    """
    all_evidence: list[CategoryEvidence] = []

    # Source 1: Breadcrumbs (highest signal weight)
    breadcrumb_text = " ".join(breadcrumbs).lower()
    if breadcrumb_text.strip():
        for cat, lex in CATEGORY_LEXICONS.items():
            pos_matches = [t for t in lex["positive"] if t in breadcrumb_text]
            neg_matches = [t for t in lex["negative"] if t in breadcrumb_text]
            if pos_matches and not neg_matches:
                all_evidence.append(CategoryEvidence(
                    source="breadcrumb",
                    snippet=breadcrumb_text[:100],
                    matched_tokens=pos_matches,
                    weight=3.0,
                ))

    # Source 2: Title
    title_lower = title.lower()
    if title_lower.strip():
        for cat, lex in CATEGORY_LEXICONS.items():
            pos_matches = [t for t in lex["positive"] if t in title_lower]
            neg_matches = [t for t in lex["negative"] if t in title_lower]
            if pos_matches and not neg_matches:
                all_evidence.append(CategoryEvidence(
                    source="title",
                    snippet=title_lower[:80],
                    matched_tokens=pos_matches,
                    weight=2.0,
                ))

    # Source 3: URL path
    url_lower = url_path.lower()
    if url_lower:
        for cat, lex in CATEGORY_LEXICONS.items():
            pos_matches = [t for t in lex["positive"] if t in url_lower]
            if pos_matches:
                all_evidence.append(CategoryEvidence(
                    source="url_path",
                    snippet=url_lower[:100],
                    matched_tokens=pos_matches,
                    weight=1.5,
                ))

    # Source 4: Product type (from enrichment)
    if product_type:
        all_evidence.append(CategoryEvidence(
            source="enrichment_product_type",
            snippet=product_type,
            matched_tokens=[product_type],
            weight=2.5,
        ))

    # Source 5: Facets (key/value pairs from PDP)
    for key, val in facets.items():
        combined = f"{key} {val}".lower()
        for cat, lex in CATEGORY_LEXICONS.items():
            pos_matches = [t for t in lex["positive"] if t in combined]
            if pos_matches:
                all_evidence.append(CategoryEvidence(
                    source="facet",
                    snippet=f"{key}: {val}"[:80],
                    matched_tokens=pos_matches,
                    weight=1.0,
                ))

    # Source 6: Description
    if description:
        desc_lower = description.lower()[:500]
        for cat, lex in CATEGORY_LEXICONS.items():
            pos_matches = [t for t in lex["positive"] if t in desc_lower]
            if pos_matches:
                all_evidence.append(CategoryEvidence(
                    source="description",
                    snippet=desc_lower[:80],
                    matched_tokens=pos_matches,
                    weight=0.5,
                ))

    return all_evidence


# ============================================================================
# C3: RULE SCORER
# ============================================================================

def _score_categories(evidence: list[CategoryEvidence]) -> dict[str, float]:
    """
    Score each category based on accumulated evidence.

    Uses positive and negative lexicon matching with weighted evidence sources.
    Returns normalized probability-like scores per category.
    """
    raw_scores: dict[str, float] = {cat: 0.0 for cat in CATEGORY_LEXICONS}

    for ev in evidence:
        for cat, lex in CATEGORY_LEXICONS.items():
            # Count how many of this evidence's tokens belong to this category's positive lexicon
            pos_hits = sum(1 for t in ev.matched_tokens if t in lex["positive"])
            neg_hits = sum(1 for t in ev.matched_tokens if t in lex["negative"])

            if pos_hits > 0:
                raw_scores[cat] += ev.weight * pos_hits
            if neg_hits > 0:
                raw_scores[cat] -= ev.weight * neg_hits * 2  # Negative evidence is stronger

    # Remove zero/negative scores
    positive_scores = {k: max(v, 0.0) for k, v in raw_scores.items() if v > 0}

    if not positive_scores:
        return {"unknown": 1.0}

    # Normalize to probabilities
    total = sum(positive_scores.values())
    if total == 0:
        return {"unknown": 1.0}

    return {k: round(v / total, 4) for k, v in sorted(positive_scores.items(), key=lambda x: -x[1])}


# ============================================================================
# MAIN CLASSIFICATION FUNCTION
# ============================================================================

def classify_item(
    *,
    title: str = "",
    breadcrumbs: list[str] | None = None,
    url_path: str = "",
    product_type: str | None = None,
    facets: dict[str, str] | None = None,
    description: str | None = None,
) -> ClassificationResult:
    """
    Classify an item into a furniture category.

    Uses all available signals (breadcrumbs, title, URL, facets, description)
    with evidence provenance for explainability and reprocessing.
    """
    evidence = _build_features(
        title=title,
        breadcrumbs=breadcrumbs or [],
        url_path=url_path,
        product_type=product_type,
        facets=facets or {},
        description=description,
    )

    probabilities = _score_categories(evidence)

    # Top 1 and top 2
    sorted_cats = sorted(probabilities.items(), key=lambda x: -x[1])
    top1_cat = sorted_cats[0][0] if sorted_cats else "unknown"
    top1_conf = sorted_cats[0][1] if sorted_cats else 0.0
    top2_conf = sorted_cats[1][1] if len(sorted_cats) > 1 else 0.0
    margin = top1_conf - top2_conf

    # Serialize evidence for storage
    evidence_dicts = [
        {
            "source": e.source,
            "snippet": e.snippet,
            "tokens": e.matched_tokens,
            "weight": e.weight,
        }
        for e in evidence
    ]

    return ClassificationResult(
        predicted_category=top1_cat,
        category_probabilities=dict(sorted_cats[:5]),  # Top 5 categories
        top1_confidence=top1_conf,
        top1_top2_margin=margin,
        classification_version=CLASSIFICATION_VERSION,
        evidence=evidence_dicts,
    )
