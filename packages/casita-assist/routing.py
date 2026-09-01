"""Pure text-routing helpers for Casita's conversation agent."""

from __future__ import annotations

import re


_WORKFLOW_PATTERNS = tuple(
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        # A workflow noun is enough to select the only route that owns Loom's
        # authoring tools. Accept the common STT split spelling, too.
        r"\b(?:n8n|work\s*flows?|automations?|workflow builders?|workflow drafts?)\b",
        # CAAL-style requests often call the resulting workflow a voice tool.
        r"\b(?:create|build|make|draft|design|write|set\s*up|install|modify|update|edit|change|delete|remove|archive)\b.{0,200}\b(?:tools?|skills?)\b",
    )
)

_NASCAR_PATTERN = re.compile(
    r"\b(?:nascar|cup\s+(?:series|race)|xfinity(?:\s+(?:series|race))?|"
    r"o['’]?\s*reilly(?:\s+auto\s+parts)?(?:\s+(?:series|race))?|"
    r"craftsman(?:\s+truck)?(?:\s+(?:series|race))?|truck\s+series)\b",
    re.IGNORECASE,
)

_SPORTS_PATTERNS = tuple(
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        r"\b(?:nfl|nba|nhl|epl|mls|football|basketball|hockey|soccer|"
        r"premier league|formula\s*(?:one|1)|f1|sports? scores?)\b",
        r"\b(?:play|race)\b.{0,80}\b(?:next|today|tonight|tomorrow|this week)\b",
        r"\b(?:scores?|standings|who won)\b.{0,80}"
        r"\b(?:game|games|race|week|today|tonight)\b",
    )
)

_NEWS_PATTERN = re.compile(
    r"\b(?:news|headlines?|current\s+events)\b",
    re.IGNORECASE,
)


def is_workflow_request(text: str) -> bool:
    """Return whether an utterance belongs to the isolated workflow route."""
    normalized = " ".join(text.casefold().split())
    return any(pattern.search(normalized) for pattern in _WORKFLOW_PATTERNS)


def is_nascar_request(text: str) -> bool:
    """Return whether an utterance specifically needs the NASCAR workflow."""
    normalized = " ".join(text.casefold().split())
    return bool(_NASCAR_PATTERN.search(normalized))


def is_sports_request(text: str) -> bool:
    """Return whether an utterance needs the live sports suite."""
    normalized = " ".join(text.casefold().split())
    return is_nascar_request(normalized) or any(
        pattern.search(normalized) for pattern in _SPORTS_PATTERNS
    )


def is_news_request(text: str) -> bool:
    """Return whether an utterance needs current Miniflux headlines."""
    normalized = " ".join(text.casefold().split())
    return bool(_NEWS_PATTERN.search(normalized))


def workflow_catalog_query(text: str) -> str:
    """Map specific requests to a stable reviewed-tool catalogue term."""
    normalized = " ".join(text.casefold().split())
    if is_nascar_request(normalized):
        return "nascar"
    if is_sports_request(normalized):
        return "sports"
    return normalized[:128]
