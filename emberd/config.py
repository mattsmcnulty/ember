"""Load emberd runtime config from options.json (gitignored; holds the localKey)."""
import json
import os

_SEARCH = [
    os.environ.get("EMBERD_OPTIONS"),
    "options.json",
    "/data/options.json",
    os.path.join(os.path.dirname(__file__), "options.json"),
]


def load() -> dict:
    for p in _SEARCH:
        if p and os.path.exists(p):
            with open(p) as f:
                return json.load(f)
    raise FileNotFoundError(
        "options.json not found. Copy options.example.json to options.json and fill it in "
        "(or set EMBERD_OPTIONS to its path)."
    )
