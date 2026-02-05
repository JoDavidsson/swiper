from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.recipes.runner import run_recipe_on_html


@dataclass(frozen=True)
class RecipeEvaluation:
    total: int
    succeeded: int
    success_rate: float
    avg_completeness: float
    hard_failures: int


def _score_from_output(out: dict) -> float:
    # Default weights from the spec
    weights = {"title": 3, "canonicalUrl": 3, "images": 2, "price.amount": 2, "price.currency": 1}
    got = 0
    total = sum(weights.values())
    if str(out.get("title") or "").strip():
        got += weights["title"]
    if str(out.get("canonicalUrl") or "").strip().startswith(("http://", "https://")):
        got += weights["canonicalUrl"]
    imgs = out.get("images")
    if isinstance(imgs, list) and len(imgs) >= 1:
        got += weights["images"]
    price = out.get("price")
    if isinstance(price, dict):
        if price.get("amount") is not None:
            got += weights["price.amount"]
        if str(price.get("currency") or "").strip():
            got += weights["price.currency"]
    return got / total if total else 0.0


def evaluate_recipe_on_pages(*, recipe: dict, pages: list[dict]) -> RecipeEvaluation:
    """
    Evaluate a recipe against a set of pages.

    Each page: { html: str, finalUrl: str }
    """
    total = len(pages)
    if total == 0:
        return RecipeEvaluation(total=0, succeeded=0, success_rate=0.0, avg_completeness=0.0, hard_failures=0)
    succeeded = 0
    hard_failures = 0
    completeness_sum = 0.0
    for p in pages:
        html = p.get("html") or ""
        final_url = p.get("finalUrl") or p.get("final_url") or ""
        rr = run_recipe_on_html(recipe=recipe, html=html, final_url=final_url)
        if rr.ok:
            succeeded += 1
            completeness_sum += _score_from_output(rr.output)
        else:
            hard_failures += 1
    success_rate = succeeded / total if total else 0.0
    avg_completeness = (completeness_sum / succeeded) if succeeded else 0.0
    return RecipeEvaluation(
        total=total,
        succeeded=succeeded,
        success_rate=success_rate,
        avg_completeness=avg_completeness,
        hard_failures=hard_failures,
    )


def passes_promotion_gate(
    evaluation: RecipeEvaluation,
    *,
    min_success_rate: float = 0.85,
    min_avg_completeness: float = 0.75,
) -> bool:
    return evaluation.success_rate >= min_success_rate and evaluation.avg_completeness >= min_avg_completeness and evaluation.hard_failures == 0

