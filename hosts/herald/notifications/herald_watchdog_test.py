#!/usr/bin/env python3

import json
from pathlib import Path
import tempfile
import unittest

import herald_watchdog as watchdog


TARGETS = [
    {"id": "one", "name": "Service One", "url": "https://one.example/"},
    {"id": "two", "name": "Service Two", "url": "https://two.example/"},
]


class WatchdogTests(unittest.TestCase):
    def test_requires_two_failures_and_deduplicates(self):
        results = {
            "one": {"healthy": False, "detail": "connection refused"},
            "two": {"healthy": True, "detail": "HTTP 200"},
        }
        first, transitions = watchdog.evaluate(TARGETS, {}, results)
        self.assertEqual([], transitions)
        self.assertEqual(1, first["one"]["failures"])

        second, transitions = watchdog.evaluate(TARGETS, first, results)
        self.assertEqual("failed", transitions[0]["kind"])
        self.assertTrue(second["one"]["notified"])

        third, transitions = watchdog.evaluate(TARGETS, second, results)
        self.assertEqual([], transitions)
        self.assertEqual(3, third["one"]["failures"])

    def test_recovery_is_immediate_after_notification(self):
        previous = {
            "one": {"failures": 4, "notified": True, "detail": "timeout"},
            "two": {"failures": 0, "notified": False, "detail": "HTTP 200"},
        }
        results = {
            "one": {"healthy": True, "detail": "HTTP 200"},
            "two": {"healthy": True, "detail": "HTTP 204"},
        }
        state, transitions = watchdog.evaluate(TARGETS, previous, results)
        self.assertEqual("recovered", transitions[0]["kind"])
        self.assertEqual(0, state["one"]["failures"])
        self.assertFalse(state["one"]["notified"])

    def test_first_healthy_run_is_silent(self):
        results = {
            "one": {"healthy": True, "detail": "HTTP 200"},
            "two": {"healthy": True, "detail": "HTTP 401"},
        }
        _, transitions = watchdog.evaluate(TARGETS, {}, results)
        self.assertEqual([], transitions)

    def test_corrupt_state_is_discarded(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            path.write_text("not-json", encoding="utf-8")
            self.assertEqual({}, watchdog.load_state(path))

    def test_state_round_trip_is_atomic(self):
        state = {"one": {"failures": 2, "notified": True, "detail": "HTTP 503"}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            watchdog.save_state(path, state)
            self.assertEqual(state, json.loads(path.read_text(encoding="utf-8")))
            self.assertEqual(0o600, path.stat().st_mode & 0o777)

    def test_target_catalog_rejects_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "targets.json"
            path.write_text(json.dumps([TARGETS[0], TARGETS[0]]), encoding="utf-8")
            with self.assertRaises(ValueError):
                watchdog.load_targets(path)

    def test_notification_prioritizes_failures(self):
        title, message, priority, tags = watchdog.notification(
            [
                {"kind": "failed", "name": "One", "detail": "HTTP 503"},
                {"kind": "recovered", "name": "Two", "detail": "HTTP 200"},
            ]
        )
        self.assertIn("1 down", title)
        self.assertIn("DOWN · One", message)
        self.assertEqual("5", priority)
        self.assertIn("rotating_light", tags)


if __name__ == "__main__":
    unittest.main()
