"""
C1: Primary-category classification (hierarchical taxonomy root).
C2: Feature builder with evidence provenance.
C3: Rule scorer with positive/negative taxonomy lexicons.
C6: Sofa profile extraction (shape/function/seat count + legacy subCategory).
C7: Room-type tagging (non-hierarchical placement tags).

Classifies items into primary furniture categories using breadcrumbs, title, URL
path, and facets as evidence. For sofas, derives orthogonal attributes:
- sofaTypeShape (single best match)
- sofaFunction (single best match, defaults to standard)
- seatCountBucket (optional)
- environment (indoor/outdoor/both/unknown)
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any


# ============================================================================
# C1: CATEGORY TAXONOMY
# ============================================================================

# Primary-category taxonomy – each category has positive and negative lexicons.
# Positive tokens boost the category score; negative tokens suppress it.
# Both Swedish and English keywords included for Swedish retailer coverage.
CATEGORY_LEXICONS: dict[str, dict[str, list[str]]] = {
    "sofa": {
        "positive": [
            "soffa", "soffor", "sofa", "sofas", "couch",
            "divansoffa", "hörnsoffa", "modulsoffa", "u-soffa", "l-soffa",
            "bäddsoffa", "bäddsoffor", "sleeper sofa", "sofa bed", "sov-soffa",
            "3-sits", "2-sits", "4-sits", "3-seater", "2-seater", "4-seater",
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
    "decor": {
        "positive": ["inredning", "dekoration", "decor", "vas", "ljusstake", "spegel", "tavla", "konst"],
        "negative": [],
    },
    "textile": {
        "positive": ["textil", "kudde", "pläd", "gardin", "curtain", "cushion", "throw"],
        "negative": [],
    },
}

CLASSIFICATION_VERSION = 3  # Bumped: hierarchical sofa profile + environment


# ============================================================================
# C6: SOFA PROFILE TAXONOMY
# ============================================================================
# Ordered by specificity – first match wins.
SOFA_TYPE_SHAPE_LEXICONS: list[dict[str, Any]] = [
    {
        "id": "u_shaped",
        "keywords": ["u-soffa", "u formad soffa", "u-formad soffa", "u-shaped sofa", "u shaped sofa", "u shape sofa"],
    },
    {
        "id": "corner",
        "keywords": [
            "hörnsoffa", "hörnsoffor", "corner sofa", "l-soffa", "l formad", "l-formad",
            "esquina",  # Spanish – IKEA multi-locale
        ],
    },
    {
        "id": "chaise",
        "keywords": [
            "divansoffa", "divan soffa", "chaise longue", "chaise lounge",
            "schäslong", "med schäslong", "chaselong", "c/chaise",
        ],
    },
    {
        "id": "modular",
        "keywords": ["modulsoffa", "modulsoffor", "modular sofa", "sektionssoffa", "byggsoffa", "sectional"],
    },
]

SOFA_FUNCTION_LEXICONS: list[dict[str, Any]] = [
    {
        "id": "sleeper",
        "keywords": ["bäddsoffa", "bäddsoffor", "sleeper sofa", "sofa bed", "sov-soffa", "sofá-cama", "sofá cama", "futon", "daybed", "dagbädd"],
    },
]

SEAT_COUNT_KEYWORDS: dict[str, list[str]] = {
    "2": ["2-sits", "2 sits", "2-sitssoffa", "2-seater", "2 seater", "tvåsits", "loveseat"],
    "3": ["3-sits", "3 sits", "3-sitssoffa", "3-seater", "3 seater", "tresits"],
    "4_plus": ["4-sits", "4 sits", "4-sitssoffa", "4-seater", "4 seater", "5-sits", "6-sits", "5-seater", "6-seater"],
}

SEAT_COUNT_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("4_plus", re.compile(r"\b([4-9]|[1-9]\d)\s*[- ]?(?:sits|seater|seat)\b", re.IGNORECASE)),
    ("3", re.compile(r"\b3\s*[- ]?(?:sits|seater|seat)\b", re.IGNORECASE)),
    ("2", re.compile(r"\b2\s*[- ]?(?:sits|seater|seat)\b", re.IGNORECASE)),
]

# Legacy sofa sub-category labels retained for compatibility in UI and filters.
SUB_CATEGORY_LABELS: dict[str, dict[str, str]] = {
    "2_seater": {"sv": "2-sitssoffa", "en": "2-Seater Sofa"},
    "3_seater": {"sv": "3-sitssoffa", "en": "3-Seater Sofa"},
    "4_seater": {"sv": "4-sitssoffa", "en": "4-Seater Sofa"},
    "corner_sofa": {"sv": "Hörnsoffa", "en": "Corner Sofa"},
    "u_sofa": {"sv": "U-soffa", "en": "U-Shaped Sofa"},
    "chaise_sofa": {"sv": "Divansoffa", "en": "Chaise Sofa"},
    "modular_sofa": {"sv": "Modulsoffa", "en": "Modular Sofa"},
    "sleeper_sofa": {"sv": "Bäddsoffa", "en": "Sleeper Sofa"},
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
    primary_category: str  # Canonical top-level category
    predicted_category: str  # Legacy alias for primary_category
    category_probabilities: dict[str, float]  # Top-N probabilities
    top1_confidence: float  # Confidence of top prediction (0.0-1.0)
    top1_top2_margin: float  # Gap between top-1 and top-2
    sofa_type_shape: str | None = None  # straight|corner|u_shaped|chaise|modular
    sofa_function: str | None = None  # standard|sleeper
    seat_count_bucket: str | None = None  # 2|3|4_plus
    environment: str = "unknown"  # indoor|outdoor|both|unknown
    sub_category: str | None = None  # Legacy sofa sub-type (C6 compatibility)
    room_types: list[str] = field(default_factory=list)  # Room placement tags (C7)
    classification_version: int = CLASSIFICATION_VERSION
    evidence: list[dict] = field(default_factory=list)  # Serializable evidence trail


# ============================================================================
# C2: FEATURE BUILDER
# ============================================================================

def _map_product_type_to_primary_category(product_type: str | None) -> str | None:
    """Map enrichment product_type values to primary-category IDs."""
    if not product_type:
        return None
    normalized = product_type.strip().lower()
    if normalized in CATEGORY_LEXICONS:
        return normalized
    if normalized in {"bed_sofa", "corner_sofa"}:
        return "sofa"
    # "outdoor" is modeled as environment, not a primary category.
    return None


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
    mapped_product_type = _map_product_type_to_primary_category(product_type)
    if mapped_product_type:
        all_evidence.append(CategoryEvidence(
            source="enrichment_product_type",
            snippet=product_type or mapped_product_type,
            matched_tokens=[mapped_product_type],
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
            pos_hits = sum(1 for t in ev.matched_tokens if t == cat or t in lex["positive"])
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
# C6: SOFA PROFILE EXTRACTORS
# ============================================================================

OUTDOOR_ENVIRONMENT_KEYWORDS = [
    "utomhus", "outdoor", "trädgård", "garden", "balkong", "patio", "terrace", "terrass",
    "altan", "utesoffa", "utemöbel", "utegrupp",
]
INDOOR_ENVIRONMENT_KEYWORDS = [
    "indoor", "inomhus", "vardagsrum", "living room", "lounge", "tv-rum",
    "sovrum", "bedroom", "kontor", "office", "hall", "hallway",
]
INDOOR_ROOM_TYPE_IDS = {"living_room", "bedroom", "office", "hallway", "kids_room"}


def _combine_text_signals(
    *,
    title: str,
    description: str | None,
    breadcrumbs: list[str] | None = None,
    url_path: str = "",
    facets: dict[str, str] | None = None,
) -> str:
    parts = [title.lower()]
    if description:
        parts.append(description.lower()[:500])
    if breadcrumbs:
        parts.append(" ".join(breadcrumbs).lower())
    if url_path:
        parts.append(url_path.lower())
    if facets:
        facet_text = " ".join(f"{k} {v}" for k, v in facets.items())
        parts.append(facet_text.lower()[:800])
    return " ".join(parts)


def _extract_sofa_type_shape(
    *,
    primary_category: str,
    text: str,
) -> str | None:
    """Extract sofa shape from combined text signals."""
    if primary_category != "sofa":
        return None

    for shape in SOFA_TYPE_SHAPE_LEXICONS:
        if any(keyword in text for keyword in shape["keywords"]):
            return shape["id"]

    return "straight"


def _extract_sofa_function(
    *,
    primary_category: str,
    text: str,
) -> str | None:
    """Extract sofa function from combined text signals."""
    if primary_category != "sofa":
        return None

    for fn in SOFA_FUNCTION_LEXICONS:
        if any(keyword in text for keyword in fn["keywords"]):
            return fn["id"]

    return "standard"


def _extract_seat_count_bucket(
    *,
    primary_category: str,
    text: str,
    seat_count: int | None = None,
) -> str | None:
    """Extract optional seat-count bucket (2|3|4_plus)."""
    if primary_category != "sofa":
        return None

    if isinstance(seat_count, int) and seat_count > 0:
        if seat_count >= 4:
            return "4_plus"
        if seat_count == 3:
            return "3"
        if seat_count == 2:
            return "2"
        return None

    for bucket, keywords in SEAT_COUNT_KEYWORDS.items():
        if any(keyword in text for keyword in keywords):
            return bucket

    for bucket, pattern in SEAT_COUNT_PATTERNS:
        if pattern.search(text):
            return bucket

    return None


def _extract_environment(
    *,
    primary_category: str,
    text: str,
    product_type: str | None,
    room_types: list[str],
) -> str:
    """
    Extract environment axis: indoor|outdoor|both|unknown.

    "unknown" is intended as internal fallback; UI may choose not to display it.
    """
    has_outdoor = any(keyword in text for keyword in OUTDOOR_ENVIRONMENT_KEYWORDS)
    has_indoor = any(keyword in text for keyword in INDOOR_ENVIRONMENT_KEYWORDS)

    normalized_product_type = (product_type or "").strip().lower()
    if normalized_product_type == "outdoor":
        has_outdoor = True

    if any(room == "outdoor" for room in room_types):
        has_outdoor = True
    if any(room in INDOOR_ROOM_TYPE_IDS for room in room_types):
        has_indoor = True

    if has_outdoor and has_indoor:
        return "both"
    if has_outdoor:
        return "outdoor"
    if has_indoor:
        return "indoor"

    # For sofas, assume indoor by default unless explicit outdoor evidence exists.
    if primary_category == "sofa":
        return "indoor"
    return "unknown"


def _derive_legacy_sub_category(
    *,
    primary_category: str,
    sofa_type_shape: str | None,
    sofa_function: str | None,
    seat_count_bucket: str | None,
) -> str | None:
    """Derive legacy subCategory for backwards-compatible filters."""
    if primary_category != "sofa":
        return None
    if sofa_function == "sleeper":
        return "sleeper_sofa"
    if sofa_type_shape == "u_shaped":
        return "u_sofa"
    if sofa_type_shape == "corner":
        return "corner_sofa"
    if sofa_type_shape == "chaise":
        return "chaise_sofa"
    if sofa_type_shape == "modular":
        return "modular_sofa"
    if seat_count_bucket == "4_plus":
        return "4_seater"
    if seat_count_bucket == "3":
        return "3_seater"
    if seat_count_bucket == "2":
        return "2_seater"
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
    seat_count: int | None = None,
) -> ClassificationResult:
    """
    Classify an item into a primary category and derive sofa profile attributes.

    Uses all available signals (breadcrumbs, title, URL, facets, description)
    with evidence provenance for explainability and reprocessing.
    """
    safe_breadcrumbs = breadcrumbs or []
    safe_facets = facets or {}
    evidence = _build_features(
        title=title,
        breadcrumbs=safe_breadcrumbs,
        url_path=url_path,
        product_type=product_type,
        facets=safe_facets,
        description=description,
    )

    probabilities = _score_categories(evidence)

    # Top 1 and top 2
    sorted_cats = sorted(probabilities.items(), key=lambda x: -x[1])
    top1_cat = sorted_cats[0][0] if sorted_cats else "unknown"
    top1_conf = sorted_cats[0][1] if sorted_cats else 0.0
    top2_conf = sorted_cats[1][1] if len(sorted_cats) > 1 else 0.0
    margin = top1_conf - top2_conf

    # C7: Extract room-type tags
    room_types = _extract_room_types(
        title=title,
        description=description,
        breadcrumbs=safe_breadcrumbs,
        url_path=url_path,
    )

    profile_text = _combine_text_signals(
        title=title,
        description=description,
        breadcrumbs=safe_breadcrumbs,
        url_path=url_path,
        facets=safe_facets,
    )
    sofa_type_shape = _extract_sofa_type_shape(primary_category=top1_cat, text=profile_text)
    sofa_function = _extract_sofa_function(primary_category=top1_cat, text=profile_text)
    seat_count_bucket = _extract_seat_count_bucket(
        primary_category=top1_cat,
        text=profile_text,
        seat_count=seat_count,
    )
    environment = _extract_environment(
        primary_category=top1_cat,
        text=profile_text,
        product_type=product_type,
        room_types=room_types,
    )
    sub_category = _derive_legacy_sub_category(
        primary_category=top1_cat,
        sofa_type_shape=sofa_type_shape,
        sofa_function=sofa_function,
        seat_count_bucket=seat_count_bucket,
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
        primary_category=top1_cat,
        predicted_category=top1_cat,
        category_probabilities=dict(sorted_cats[:5]),  # Top 5 categories
        top1_confidence=top1_conf,
        top1_top2_margin=margin,
        sofa_type_shape=sofa_type_shape,
        sofa_function=sofa_function,
        seat_count_bucket=seat_count_bucket,
        environment=environment,
        sub_category=sub_category,
        room_types=room_types,
        classification_version=CLASSIFICATION_VERSION,
        evidence=evidence_dicts,
    )
