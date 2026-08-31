from __future__ import annotations

import unittest
from unittest import mock

import codex_news_api as news


class RequestTests(unittest.TestCase):
    def test_defaults_and_aliases_are_bounded(self) -> None:
        request = news.normalize_request(
            {
                "query": "  kernel   security  ",
                "category": "tech",
                "hours": 500,
                "limit": 99,
            }
        )
        self.assertEqual(request["query"], "kernel security")
        self.assertEqual(request["category"], "Technology")
        self.assertEqual(request["hours"], 168)
        self.assertEqual(request["limit"], 10)

    def test_unknown_fields_and_categories_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported"):
            news.normalize_request({"command": "delete"})
        with self.assertRaisesRegex(ValueError, "unknown news category"):
            news.normalize_request({"category": "secrets"})


class QueryTests(unittest.TestCase):
    @mock.patch("codex_news_api.subprocess.run")
    def test_query_uses_psql_arguments_without_shell(self, run: mock.Mock) -> None:
        run.return_value.stdout = '[{"id":1,"title":"NixOS release"}]\n'
        articles = news.query_entries(
            {
                "query": "nixos -crypto",
                "category": "Technology",
                "hours": 24,
                "limit": 5,
            }
        )
        self.assertEqual(articles[0]["id"], 1)
        arguments = run.call_args.args[0]
        self.assertIn("--set=query=nixos -crypto", arguments)
        self.assertNotIn("shell", run.call_args.kwargs)
        self.assertIn("websearch_to_tsquery", run.call_args.kwargs["input"])
        self.assertEqual(run.call_args.kwargs["timeout"], 8)

    def test_response_contains_only_bounded_metadata(self) -> None:
        response = news.build_response(
            {"query": "", "category": "Cybersecurity", "hours": 24, "limit": 5},
            [
                {
                    "id": 1,
                    "title": "A\nheadline",
                    "url": "https://example.test/article",
                    "published_at": "2026-08-31T10:00:00Z",
                    "feed": "Example",
                    "category": "Cybersecurity",
                    "content": "must not escape",
                }
            ],
        )
        self.assertEqual(response["count"], 1)
        self.assertNotIn("content", response["articles"][0])
        self.assertIn("A headline", response["message"])


if __name__ == "__main__":
    unittest.main()
