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


def is_workflow_request(text: str) -> bool:
    """Return whether an utterance belongs to the isolated workflow route."""
    normalized = " ".join(text.casefold().split())
    return any(pattern.search(normalized) for pattern in _WORKFLOW_PATTERNS)
