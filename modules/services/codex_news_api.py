"""Bounded read-only Miniflux news search for Casita."""

from __future__ import annotations

import argparse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
import os
import re
import subprocess
from typing import Any


MAX_BODY_BYTES = 4096
MAX_QUERY_LENGTH = 120
MAX_LIMIT = 10
MAX_HOURS = 168
DEFAULT_LIMIT = 5
DEFAULT_HOURS = 24

CATEGORIES = {
    "": "",
    "all": "",
    "ai": "AI & Data",
    "artificial intelligence": "AI & Data",
    "business": "Business & Economics",
    "chicago": "Chicago",
    "climate": "Climate & Environment",
    "culture": "Culture & Ideas",
    "cyber": "Cybersecurity",
    "cybersecurity": "Cybersecurity",
    "devops": "Programming & DevOps",
    "gaming": "Gaming",
    "homelab": "Homelab & Self-Hosting",
    "linux": "Linux & Open Source",
    "news": "World News",
    "open source": "Linux & Open Source",
    "politics": "US & Politics",
    "privacy": "Privacy & Digital Rights",
    "programming": "Programming & DevOps",
    "science": "Science & Space",
    "security": "Cybersecurity",
    "space": "Science & Space",
    "tech": "Technology",
    "technology": "Technology",
    "world": "World News",
}

SQL = """
SELECT COALESCE(json_agg(row_to_json(article)), '[]'::json)::text
FROM (
  SELECT
    e.id,
    left(regexp_replace(e.title, '[[:space:]]+', ' ', 'g'), 200) AS title,
    e.url,
    e.published_at,
    left(regexp_replace(f.title, '[[:space:]]+', ' ', 'g'), 100) AS feed,
    c.title AS category
  FROM entries AS e
  JOIN feeds AS f ON f.id = e.feed_id
  JOIN categories AS c ON c.id = f.category_id
  WHERE e.user_id = 1
    AND e.published_at >= now() - make_interval(hours => {hours})
    AND (:'category' = '' OR c.title = :'category')
    AND (:'query' = '' OR e.document_vectors @@ websearch_to_tsquery('simple', :'query'))
  ORDER BY e.published_at DESC
  LIMIT {limit}
) AS article;
"""


def clean_text(value: Any, maximum: int) -> str:
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", str(value or ""))
    return re.sub(r"\s+", " ", text).strip()[:maximum]


def normalize_request(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ValueError("body must be a JSON object")
    unknown = set(payload) - {"query", "category", "hours", "limit"}
    if unknown:
        raise ValueError("unsupported request fields")

    query = clean_text(payload.get("query"), MAX_QUERY_LENGTH)
    raw_category = clean_text(payload.get("category"), 60).lower()
    if raw_category not in CATEGORIES:
        raise ValueError("unknown news category")
    category = CATEGORIES[raw_category]

    try:
        hours = int(payload.get("hours", DEFAULT_HOURS))
        limit = int(payload.get("limit", DEFAULT_LIMIT))
    except (TypeError, ValueError) as error:
        raise ValueError("hours and limit must be integers") from error

    return {
        "query": query,
        "category": category,
        "hours": min(MAX_HOURS, max(1, hours)),
        "limit": min(MAX_LIMIT, max(1, limit)),
    }


def query_entries(request: dict[str, Any]) -> list[dict[str, Any]]:
    sql = SQL.format(hours=request["hours"], limit=request["limit"])
    try:
        result = subprocess.run(
            [
                "psql",
                "--no-align",
                "--tuples-only",
                "--quiet",
                "--set=ON_ERROR_STOP=1",
                f"--set=query={request['query']}",
                f"--set=category={request['category']}",
                "--username=codex-news",
                "--dbname=miniflux",
            ],
            check=True,
            capture_output=True,
            input=sql,
            text=True,
            timeout=8,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        logging.error("Miniflux query failed: %s", getattr(error, "stderr", "timeout"))
        raise RuntimeError("news database query failed") from error
    articles = json.loads(result.stdout.strip() or "[]")
    if not isinstance(articles, list):
        raise RuntimeError("database returned an invalid article list")
    return [article for article in articles if isinstance(article, dict)]


def build_response(
    request: dict[str, Any], articles: list[dict[str, Any]]
) -> dict[str, Any]:
    safe_articles = [
        {
            "id": int(article.get("id", 0)),
            "title": clean_text(article.get("title"), 200),
            "url": clean_text(article.get("url"), 500),
            "publishedAt": clean_text(article.get("published_at"), 50),
            "feed": clean_text(article.get("feed"), 100),
            "category": clean_text(article.get("category"), 60),
        }
        for article in articles
    ]
    scope = request["category"] or "all categories"
    subject = f" matching {request['query']}" if request["query"] else ""
    if not safe_articles:
        message = (
            f"I couldn't find news{subject} in {scope} from the last "
            f"{request['hours']} hours."
        )
    else:
        headlines = "; ".join(
            f"{index}. {article['title']}, from {article['feed']}"
            for index, article in enumerate(safe_articles, start=1)
        )
        message = f"Here are the latest {scope} headlines{subject}: {headlines}."

    return {
        "ok": True,
        "message": message,
        "source": "Miniflux",
        "query": request["query"],
        "category": request["category"] or None,
        "hours": request["hours"],
        "count": len(safe_articles),
        "articles": safe_articles,
    }


def handler() -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "CodexNews/1"

        def log_message(self, format: str, *args: Any) -> None:
            logging.info("http %s - %s", self.address_string(), format % args)

        def send_json(self, status: int, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            if self.path == "/healthz":
                self.send_json(HTTPStatus.OK, {"status": "ok"})
                return
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})

        def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            if self.path != "/v1/news":
                self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            if length <= 0 or length > MAX_BODY_BYTES:
                self.send_json(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "invalid body size"}
                )
                return
            try:
                request = normalize_request(json.loads(self.rfile.read(length)))
                response = build_response(request, query_entries(request))
            except (json.JSONDecodeError, ValueError) as error:
                self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(error)[:300]})
                return
            except Exception as error:
                logging.exception("news query failed")
                self.send_json(HTTPStatus.BAD_GATEWAY, {"error": str(error)[:300]})
                return
            self.send_json(HTTPStatus.OK, response)

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("serve",), nargs="?", default="serve")
    args = parser.parse_args()
    logging.basicConfig(level=os.environ.get("CODEX_NEWS_LOG_LEVEL", "INFO"))
    if args.command == "serve":
        ThreadingHTTPServer(("127.0.0.1", 8090), handler()).serve_forever()


if __name__ == "__main__":
    main()
