"""
D4: Weekly calibration job.

Adjusts classification thresholds based on reviewer labels.
Designed to be called as a scheduled endpoint or manual trigger.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone


@dataclass
class CalibrationResult:
    """Output from a calibration run."""
    total_labels: int
    accuracy_before: float
    accuracy_after: float
    threshold_adjustments: dict[str, dict]
    recommended_accept_threshold: float
    recommended_reject_threshold: float
    calibrated_at: str = ""

    def __post_init__(self):
        if not self.calibrated_at:
            self.calibrated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def run_calibration(db) -> CalibrationResult:
    """
    Analyze reviewer labels and compute optimal classification thresholds.

    Algorithm:
    1. Load all reviewer labels with original confidence scores
    2. For each label, check if the classification was correct
    3. Find the confidence threshold that maximizes F1 score
    4. Return recommended threshold adjustments
    """
    labels = list(db.collection("reviewerLabels").stream())
    if not labels:
        return CalibrationResult(
            total_labels=0,
            accuracy_before=0.0,
            accuracy_after=0.0,
            threshold_adjustments={},
            recommended_accept_threshold=0.60,
            recommended_reject_threshold=0.20,
        )

    # Extract confidence + correctness pairs
    entries: list[tuple[float, bool]] = []
    for doc in labels:
        data = doc.to_dict() or {}
        original = data.get("originalClassification", {})
        conf = original.get("top1Confidence", 0.5)
        action = data.get("action", "")
        correct_cat = data.get("correctCategory")

        # Label is "correct" if reviewer accepted or reclassified to same category
        original_cat = original.get("primaryCategory", original.get("predictedCategory"))
        is_correct = action == "accept" or (
            correct_cat is not None and correct_cat == original_cat
        )
        entries.append((conf, is_correct))

    if not entries:
        return CalibrationResult(
            total_labels=0,
            accuracy_before=0.0,
            accuracy_after=0.0,
            threshold_adjustments={},
            recommended_accept_threshold=0.60,
            recommended_reject_threshold=0.20,
        )

    # Current accuracy (with default threshold of 0.60)
    current_correct = sum(1 for conf, correct in entries if correct and conf >= 0.60)
    current_total = sum(1 for conf, _ in entries if conf >= 0.60)
    accuracy_before = current_correct / current_total if current_total > 0 else 0.0

    # Grid search for best accept threshold (maximize precision while keeping recall > 0.5)
    best_threshold = 0.60
    best_f1 = 0.0

    for threshold in [t / 100 for t in range(30, 90, 5)]:
        tp = sum(1 for conf, correct in entries if conf >= threshold and correct)
        fp = sum(1 for conf, correct in entries if conf >= threshold and not correct)
        fn = sum(1 for conf, correct in entries if conf < threshold and correct)

        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0

        if f1 > best_f1:
            best_f1 = f1
            best_threshold = threshold

    # Compute reject threshold (where precision drops below 0.3)
    reject_threshold = 0.20
    for threshold in [t / 100 for t in range(10, 50, 5)]:
        tp = sum(1 for conf, correct in entries if abs(conf - threshold) < 0.05 and correct)
        total_at = sum(1 for conf, _ in entries if abs(conf - threshold) < 0.05)
        if total_at > 0 and tp / total_at < 0.3:
            reject_threshold = threshold
            break

    # New accuracy
    new_correct = sum(1 for conf, correct in entries if correct and conf >= best_threshold)
    new_total = sum(1 for conf, _ in entries if conf >= best_threshold)
    accuracy_after = new_correct / new_total if new_total > 0 else 0.0

    return CalibrationResult(
        total_labels=len(entries),
        accuracy_before=round(accuracy_before, 3),
        accuracy_after=round(accuracy_after, 3),
        threshold_adjustments={
            "accept": {"old": 0.60, "new": round(best_threshold, 2)},
            "reject": {"old": 0.20, "new": round(reject_threshold, 2)},
        },
        recommended_accept_threshold=round(best_threshold, 2),
        recommended_reject_threshold=round(reject_threshold, 2),
    )
