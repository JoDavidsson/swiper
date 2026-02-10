"""Tests for hierarchical + orthogonal taxonomy outputs in sorting classifier."""

from app.sorting.classifier import classify_item


def test_corner_sofa_maps_to_primary_sofa_and_shape_axis() -> None:
    result = classify_item(
        title="Hörnsoffa Vega 4-sits",
        description="Modern modulär hörnsoffa",
        breadcrumbs=["Möbler", "Soffor", "Hörnsoffor"],
        url_path="/soffor/hornsoffor/vega",
    )

    assert result.primary_category == "sofa"
    assert result.predicted_category == "sofa"  # Legacy alias
    assert result.sofa_type_shape == "corner"
    assert result.sofa_function == "standard"
    assert result.seat_count_bucket == "4_plus"
    assert result.environment == "indoor"
    assert result.sub_category == "corner_sofa"
    assert "corner_sofa" not in result.category_probabilities


def test_sleeper_sofa_maps_to_function_axis() -> None:
    result = classify_item(
        title="Nora bäddsoffa 3-sits",
        description="Bäddsoffa med förvaring",
        breadcrumbs=["Möbler", "Soffor", "Bäddsoffor"],
        url_path="/soffor/baddsoffor/nora",
    )

    assert result.primary_category == "sofa"
    assert result.sofa_function == "sleeper"
    assert result.seat_count_bucket == "3"
    assert result.sub_category == "sleeper_sofa"


def test_environment_can_be_both_when_mixed_indoor_outdoor_signals() -> None:
    result = classify_item(
        title="Outdoor soffa Lima",
        description="Utomhus modell som även passar i vardagsrum",
        breadcrumbs=["Outdoor", "Sofas"],
        url_path="/outdoor/sofas/lima",
        product_type="outdoor",
    )

    assert result.primary_category == "sofa"
    assert "outdoor" in result.room_types
    assert "living_room" in result.room_types
    assert result.environment == "both"


def test_non_sofa_category_has_no_sofa_profile_fields() -> None:
    result = classify_item(
        title="Matbord ek 180 cm",
        description="Massivt träbord för kök",
        breadcrumbs=["Möbler", "Matbord"],
        url_path="/matbord/ek-180",
    )

    assert result.primary_category == "dining_table"
    assert result.sofa_type_shape is None
    assert result.sofa_function is None
    assert result.seat_count_bucket is None
    assert result.sub_category is None


def test_numeric_seat_count_is_used_when_available() -> None:
    result = classify_item(
        title="Modulsoffa Atlas",
        description="Byggbar soffa",
        breadcrumbs=["Möbler", "Soffor"],
        url_path="/soffor/modulsoffa-atlas",
        seat_count=5,
    )

    assert result.primary_category == "sofa"
    assert result.sofa_type_shape == "modular"
    assert result.seat_count_bucket == "4_plus"
