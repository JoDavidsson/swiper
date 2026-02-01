"""Extraction: JSON-LD, heuristics, optional LLM. Default: JSON-LD + heuristics."""

from app.extraction.default import extract_product_list, extract_product_detail

__all__ = ["extract_product_list", "extract_product_detail"]
