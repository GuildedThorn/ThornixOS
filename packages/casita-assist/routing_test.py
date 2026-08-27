"""Regression tests for Casita's deterministic workflow routing."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).with_name("routing.py")
SPEC = importlib.util.spec_from_file_location("casita_routing", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
ROUTING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ROUTING)


class WorkflowRoutingTests(unittest.TestCase):
    def test_creation_phrasings_use_workflow_route(self) -> None:
        prompts = (
            "Make a workflow to give me the NFL football scores for the week",
            "Build me an automation that checks the football scores",
            "Create an n8n workflow for weekly scores",
            "Please draft a work flow that checks ESPN",
            "Set up a voice tool for NFL results",
            "Make me a tool that gets NFL scores",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertTrue(ROUTING.is_workflow_request(prompt))

    def test_workflow_queries_and_edits_use_workflow_route(self) -> None:
        prompts = (
            "List the Loom workflows I can access",
            "Inspect the ThornFleetHealth workflow",
            "Edit my model-safe workflow draft",
            "Archive that automation",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertTrue(ROUTING.is_workflow_request(prompt))

    def test_unrelated_requests_stay_out_of_workflow_route(self) -> None:
        prompts = (
            "Make the living room warmer",
            "What is the weather outside?",
            "Is Loom online?",
            "Tell me how photosynthesis works",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertFalse(ROUTING.is_workflow_request(prompt))

    def test_live_sports_phrasings_use_sports_route(self) -> None:
        prompts = (
            "Give me the NFL scores for this week",
            "When do the Bears play next?",
            "Show me the NBA standings",
            "Who won the Formula One race?",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertTrue(ROUTING.is_sports_request(prompt))

    def test_unrelated_scores_stay_out_of_sports_route(self) -> None:
        prompts = (
            "What is the SOC risk score?",
            "Is Loom online?",
            "Score this deployment from one to ten",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertFalse(ROUTING.is_sports_request(prompt))

    def test_sports_workflow_search_uses_reviewed_catalogue_term(self) -> None:
        prompts = (
            "NFL",
            "NFL scores for the week",
            "football game scores",
        )
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.assertEqual(ROUTING.workflow_catalog_query(prompt), "sports")

    def test_other_workflow_search_terms_are_preserved(self) -> None:
        self.assertEqual(
            ROUTING.workflow_catalog_query("  Weekly   backup reports  "),
            "weekly backup reports",
        )


if __name__ == "__main__":
    unittest.main()
