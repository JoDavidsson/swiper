from __future__ import annotations

from app.sorting.policy import build_surface_policies, classify_and_decide


def _base_item(title: str = "Modern sofa collectionxyz") -> dict:
    return {
        "title": title,
        "breadcrumbs": ["Furniture", "Sofas"],
        "canonicalUrl": "https://example.com/sofas/modern-sofa",
        "productType": "sofa",
        "descriptionShort": "A modern 3-seater sofa for living room.",
        "seatCount": 3,
        "images": ["https://img.example.com/1.jpg"],
        "priceAmount": 12000,
        "priceCurrency": "SEK",
        "completenessScore": 0.92,
        "sourceId": "test_source",
        "isActive": True,
    }


def _training_config(runtime_status: str = "validated") -> dict:
    return {
        "byCategory": {
            "sofa": {
                "runtimeStatus": runtime_status,
                "sourceCategoryRejectTokens": {
                    "test_source": {
                        "sofa": ["collectionxyz"],
                    }
                },
                "sourceCategoryMinConfidence": {},
                "sourceRequireImages": {},
            }
        }
    }


def test_training_rules_active_mode_can_force_reject() -> None:
    result = classify_and_decide(
        item_id="item_active_reject",
        item_data=_base_item(),
        training_config=_training_config(runtime_status="validated"),
        training_mode="active",
    )

    assert result["trainingRules"]["mode"] == "active"
    assert result["trainingRules"]["wouldReject"] is True
    assert result["trainingRules"]["appliedSurfaces"]
    assert all(
        decision["decision"] == "REJECT"
        for decision in result["decisions"].values()
    )


def test_training_rules_shadow_mode_keeps_original_decision() -> None:
    result = classify_and_decide(
        item_id="item_shadow",
        item_data=_base_item(),
        training_config=_training_config(runtime_status="validated"),
        training_mode="shadow",
    )

    assert result["trainingRules"]["mode"] == "shadow"
    assert result["trainingRules"]["wouldReject"] is True
    assert result["trainingRules"]["appliedSurfaces"] == []
    assert result["trainingRules"]["shadowSurfaces"]
    assert any(
        decision.get("trainingShadowOverride") is not None
        for decision in result["decisions"].values()
    )


def test_training_rules_active_mode_ignores_unvalidated_config() -> None:
    result = classify_and_decide(
        item_id="item_unvalidated",
        item_data=_base_item(),
        training_config=_training_config(runtime_status="shadow_only"),
        training_mode="active",
    )

    assert result["trainingRules"]["mode"] == "active"
    assert result["trainingRules"]["wouldReject"] is False
    assert result["trainingRules"]["appliedSurfaces"] == []
    assert "training_rule_not_validated:shadow_only" in result["trainingRules"]["reasons"]
    assert any(
        decision["decision"] != "REJECT" for decision in result["decisions"].values()
    )


def test_completeness_falls_back_to_extraction_meta() -> None:
    item = _base_item(title="Sofa with extractionMeta completeness")
    item.pop("completenessScore", None)
    item["extractionMeta"] = {"completeness": 0.05}
    result = classify_and_decide(
        item_id="item_meta_completeness",
        item_data=item,
        training_mode="off",
    )
    decision = result["decisions"]["swiper_deck_sofas"]
    assert decision["decision"] == "REJECT"
    assert any("low_completeness:0.05" in reason for reason in decision["reasonCodes"])


def test_runtime_policy_overrides_change_thresholds() -> None:
    policies = build_surface_policies(
        {
            "acceptThreshold": 1.2,
            "surfacePolicies": {
                "swiper_deck_sofas": {
                    "rejectThreshold": 1.1,
                    "minCompleteness": 0.4,
                }
            },
        }
    )
    result = classify_and_decide(
        item_id="item_policy_override",
        item_data=_base_item(),
        surface_policies=policies,
        training_mode="off",
    )
    assert result["decisions"]["swiper_deck_sofas"]["decision"] == "REJECT"
