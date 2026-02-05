from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class DriftResult:
    triggered: bool
    reasons: list[str]
    baseline_success_rate: float | None
    baseline_avg_completeness: float | None


def check_drift(
    *,
    current_success_rate: float,
    current_avg_completeness: float,
    baseline_success_rate: float | None,
    baseline_avg_completeness: float | None,
    min_success_rate: float = 0.70,
    max_completeness_drop: float = 0.20,
) -> DriftResult:
    reasons: list[str] = []

    if current_success_rate < min_success_rate:
        reasons.append(f"success_rate_below_{min_success_rate}")

    if baseline_avg_completeness is not None:
        drop = baseline_avg_completeness - current_avg_completeness
        if drop >= max_completeness_drop:
            reasons.append(f"avg_completeness_drop_{max_completeness_drop}")

    return DriftResult(
        triggered=bool(reasons),
        reasons=reasons,
        baseline_success_rate=baseline_success_rate,
        baseline_avg_completeness=baseline_avg_completeness,
    )

