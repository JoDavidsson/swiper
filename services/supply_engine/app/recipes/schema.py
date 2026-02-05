from __future__ import annotations

from dataclasses import dataclass
from typing import Any


class RecipeError(ValueError):
    pass


@dataclass(frozen=True)
class RecipeMeta:
    recipe_id: str
    version: int


def validate_recipe_json(recipe: dict) -> None:
    if not isinstance(recipe, dict):
        raise RecipeError("Recipe must be an object")
    for k in ("recipeId", "version", "strategies"):
        if k not in recipe:
            raise RecipeError(f"Missing required key: {k}")
    if not isinstance(recipe.get("recipeId"), str) or not recipe["recipeId"].strip():
        raise RecipeError("recipeId must be a non-empty string")
    if not isinstance(recipe.get("version"), int) or recipe["version"] <= 0:
        raise RecipeError("version must be a positive integer")
    if not isinstance(recipe.get("strategies"), list) or not recipe["strategies"]:
        raise RecipeError("strategies must be a non-empty array")

    for s in recipe["strategies"]:
        if not isinstance(s, dict):
            raise RecipeError("strategy must be an object")
        if not s.get("enabled", True):
            continue
        if "type" not in s:
            raise RecipeError("strategy missing type")
        if s["type"] not in ("jsonld", "embedded_json", "dom"):
            raise RecipeError(f"Unsupported strategy type: {s['type']}")
        if "fieldMap" not in s or not isinstance(s["fieldMap"], dict):
            raise RecipeError("strategy fieldMap must be an object")

    # Validators are optional, but if present must be list of dicts
    validators = recipe.get("validators")
    if validators is not None:
        if not isinstance(validators, list):
            raise RecipeError("validators must be an array")
        for v in validators:
            if not isinstance(v, dict) or "field" not in v or "op" not in v:
                raise RecipeError("validator must include field and op")


def get_meta(recipe: dict) -> RecipeMeta:
    validate_recipe_json(recipe)
    return RecipeMeta(recipe_id=str(recipe["recipeId"]), version=int(recipe["version"]))

