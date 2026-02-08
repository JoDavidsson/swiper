"""
C1: Generic category classification (replaces sofa-only confidence).
C2: Feature builder with evidence provenance.
C3: Rule scorer with positive/negative taxonomy lexicons.
C6: Sub-category extraction (sofa sub-types from title/description).
C7: Room-type tagging (non-hierarchical placement tags).

Classifies items into furniture categories using breadcrumbs, title, URL path,
and facets as evidence. Each classification carries confidence, evidence trail,
and version for reprocessing.
"""
from __future__ import annotations

import re
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
        "negative": [
            "soffbord", "soffkudde", "sofftäcke", "sofa table", "sofa cushion",
            "dynset", "sittdyna", "ryggdyna", "dyna soffa", "soffdyna",
            "sofföverdrag", "överdrag soffa", "sofa cover", "klädsel",
        ],
    },
    "armchair": {
        "positive": ["fåtölj", "fåtöljer", "armchair", "armchairs", "karmstol", "öronlappsfåtölj", "snurrstol"],
        "negative": [],
    },
    "bed_sofa": {
        "positive": ["bäddsoffa", "bäddsoffor", "sleeper sofa", "sofa bed", "sov-soffa"],
        "negative": ["dynset", "sittdyna", "ryggdyna", "soffdyna", "överdrag"],
    },
    "corner_sofa": {
        "positive": ["hörnsoffa", "hörnsoffor", "corner sofa", "divansoffa", "l-soffa", "u-soffa"],
        "negative": ["dynset", "sittdyna", "ryggdyna", "soffdyna", "överdrag"],
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

CLASSIFICATION_VERSION = 2  # Bumped: added subCategory + roomTypes


# ============================================================================
# C6: SOFA SUB-CATEGORY TAXONOMY
# ============================================================================
# Ordered by specificity – first match wins. Checked against title + description.

SOFA_SUB_CATEGORIES: list[dict[str, Any]] = [
    {
        "id": "sleeper_sofa",
        "label": "Bäddsoffa",
        "label_en": "Sleeper Sofa",
        "keywords": ["bäddsoffa", "bäddsoffor", "sleeper sofa", "sofa bed", "sov-soffa", "sofá-cama", "sofá cama"],
    },
    {
        "id": "u_sofa",
        "label": "U-soffa",
        "label_en": "U-Shaped Sofa",
        "keywords": ["u-soffa", "u-formad soffa", "u-shaped sofa", "u shaped"],
    },
    {
        "id": "corner_sofa",
        "label": "Hörnsoffa",
        "label_en": "Corner Sofa",
        "keywords": [
            "hörnsoffa", "hörnsoffor", "corner sofa", "l-soffa", "l-formad",
            "esquina",  # Spanish – IKEA multi-locale
        ],
    },
    {
        "id": "chaise_sofa",
        "label": "Divansoffa",
        "label_en": "Chaise Sofa",
        "keywords": [
            "divansoffa", "divan soffa", "chaise longue", "chaise lounge",
            "schäslong", "med schäslong", "c/chaise",
        ],
    },
    {
        "id": "modular_sofa",
        "label": "Modulsoffa",
        "label_en": "Modular Sofa",
        "keywords": ["modulsoffa", "modulsoffor", "modular sofa", "sektionssoffa", "byggsoffa"],
    },
    {
        "id": "4_seater",
        "label": "4-sitssoffa",
        "label_en": "4-Seater Sofa",
        "keywords": ["4-sits", "4 sits", "4-sitssoffa", "4-seater", "4 seater", "4 asientos"],
    },
    {
        "id": "3_seater",
        "label": "3-sitssoffa",
        "label_en": "3-Seater Sofa",
        "keywords": ["3-sits", "3 sits", "3-sitssoffa", "3-seater", "3 seater", "3 asientos"],
    },
    {
        "id": "2_seater",
        "label": "2-sitssoffa",
        "label_en": "2-Seater Sofa",
        "keywords": ["2-sits", "2 sits", "2-sitssoffa", "2-seater", "2 seater", "2 asientos", "loveseat"],
    },
]

# Lookup map for sub-category labels
SUB_CATEGORY_LABELS: dict[str, dict[str, str]] = {
    sc["id"]: {"sv": sc["label"], "en": sc["label_en"]}
    for sc in SOFA_SUB_CATEGORIES
}


# ============================================================================
# C7: ROOM-TYPE TAXONOMY (non-hierarchical tags)
# ============================================================================
# Multiple room types can apply to a single item (e.g., a sofa can be
# "living_room" + "outdoor").

ROOM_TYPE_LEXICONS: list[dict[str, Any]] = [
    {
        "id": "living_room",
        "label": "Vardagsrum",
        "label_en": "Living Room",
        "keywords": [
            "vardagsrum", "living room", "living-room", "lounge",
            "vardagsrumssoffa", "tv-rum",
        ],
    },
    {
        "id": "bedroom",
        "label": "Sovrum",
        "label_en": "Bedroom",
        "keywords": ["sovrum", "bedroom", "sängkammare"],
    },
    {
        "id": "outdoor",
        "label": "Utomhus",
        "label_en": "Outdoor",
        "keywords": [
            "utomhus", "outdoor", "trädgård", "balkong", "altan",
            "utesoffa", "utemöbel", "garden", "patio", "terrace", "terrass",
        ],
    },
    {
        "id": "office",
        "label": "Kontor",
        "label_en": "Office",
        "keywords": ["kontor", "office", "arbetsrum", "hemmakontor", "home office"],
    },
    {
        "id": "hallway",
        "label": "Hall",
        "label_en": "Hallway",
        "keywords": ["hall", "entré", "hallway", "entrance", "foajé"],
    },
    {
        "id": "kids_room",
        "label": "Barnrum",
        "label_en": "Kids Room",
        "keywords": ["barnrum", "kids room", "barnsoffa", "kids", "children"],
    },
]


@dataclass
class CategoryEvidence:
    """A single piece of evidence for a classification."""
    source: str  # "breadcrumb", "title", "url_path", "facet", "jsonld_type"
    snippet: str  # The actual text that matched
    matched_tokens: list[str]  # Which lexicon tokens matched
    weight: float = 1.0  # How much this evidence contributes


@dataclass
class ClassificationResult:
    """Output of the category classifier (C1 + C6 + C7)."""
    predicted_category: str  # Top-1 predicted category
    category_probabilities: dict[str, float]  # Top-N probabilities
    top1_confidence: float  # Confidence of top prediction (0.0-1.0)
    top1_top2_margin: float  # Gap between top-1 and top-2
    sub_category: str | None = None  # Sofa sub-type (C6), e.g., "3_seater"
    room_types: list[str] = field(default_factory=list)  # Room placement tags (C7)
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
# C6: SUB-CATEGORY EXTRACTOR
# ============================================================================

def _extract_sub_category(
    *,
    title: str,
    description: str | None,
    predicted_category: str,
) -> str | None:
    """
    Extract sofa sub-type from title and description text.

    Only runs for sofa-family categories (sofa, corner_sofa, bed_sofa).
    Returns the most specific matching sub-category ID, or None.
    Ordered by specificity – first match wins.
    """
    # Only extract sub-categories for sofa-family items
    sofa_categories = {"sofa", "corner_sofa", "bed_sofa"}
    if predicted_category not in sofa_categories:
        return None

    # Combine title + description for matching
    text = title.lower()
    if description:
        text += " " + description.lower()[:500]

    for sub_cat in SOFA_SUB_CATEGORIES:
        for keyword in sub_cat["keywords"]:
            if keyword in text:
                return sub_cat["id"]

    return None


# ============================================================================
# C7: ROOM-TYPE EXTRACTOR
# ============================================================================

def _extract_room_types(
    *,
    title: str,
    description: str | None,
    breadcrumbs: list[str],
    url_path: str,
) -> list[str]:
    """
    Extract room-type placement tags from title, description, breadcrumbs, and URL.

    Returns a list of room-type IDs (non-hierarchical, multiple can apply).
    """
    # Combine all text signals
    text = title.lower()
    if description:
        text += " " + description.lower()[:500]
    text += " " + " ".join(breadcrumbs).lower()
    text += " " + url_path.lower()

    matched_rooms: list[str] = []
    for room in ROOM_TYPE_LEXICONS:
        for keyword in room["keywords"]:
            if keyword in text:
                matched_rooms.append(room["id"])
                break  # Only add each room type once

    return matched_rooms


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
    Classify an item into a furniture category, extract sub-category, and tag room types.

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

    # C6: Extract sofa sub-category
    sub_category = _extract_sub_category(
        title=title,
        description=description,
        predicted_category=top1_cat,
    )

    # C7: Extract room-type tags
    room_types = _extract_room_types(
        title=title,
        description=description,
        breadcrumbs=breadcrumbs or [],
        url_path=url_path,
    )

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
        sub_category=sub_category,
        room_types=room_types,
        classification_version=CLASSIFICATION_VERSION,
        evidence=evidence_dicts,
    )
