"""
Load sources from config JSON (MVP) or Firestore later.
"""
import json
import os
from pathlib import Path


def get_sources_from_config():
    """Load sources from config/sources.json or env SOURCES_JSON path."""
    path = os.environ.get("SOURCES_JSON")
    if path and os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data.get("sources", [])
    # Default: repo config or inline stub
    base = Path(__file__).resolve().parent.parent.parent.parent
    config_path = base / "config" / "sources.json"
    if config_path.is_file():
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            sources = data.get("sources", [])
            for s in sources:
                if "feedUrl" in s and not s["feedUrl"].startswith("http"):
                    s["feedUrl"] = str(base / s["feedUrl"])
            return sources
    return [
        {
            "id": "sample_feed",
            "name": "Sample feed",
            "mode": "feed",
            "isEnabled": True,
            "baseUrl": "",
            "rateLimitRps": 1,
            "feedUrl": str(base / "sample_data" / "sample_feed.csv"),
            "feedFormat": "csv",
        }
    ]
