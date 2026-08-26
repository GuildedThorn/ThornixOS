"""Tests for Casita's idempotent Home Assistant storage migration."""

from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).with_name("casita-ha-storage.py")
SPEC = importlib.util.spec_from_file_location("casita_ha_storage", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Unable to load casita-ha-storage.py")
storage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(storage)


DECK_ENTRY_ID = "deck-ollama-entry"
WORKFLOW_SUBENTRY_ID = "workflow-subentry"


def config_entries_document() -> dict:
    return {
        "data": {
            "entries": [
                {
                    "created_at": "2026-01-01T00:00:00+00:00",
                    "data": {"url": "http://172.16.25.26:11434"},
                    "disabled_by": None,
                    "discovery_keys": {},
                    "domain": "ollama",
                    "entry_id": DECK_ENTRY_ID,
                    "minor_version": 3,
                    "modified_at": "2026-01-01T00:00:00+00:00",
                    "options": {},
                    "pref_disable_new_entities": False,
                    "pref_disable_polling": False,
                    "source": "user",
                    "subentries": [
                        {
                            "data": {"model": "llama3.2:3b"},
                            "subentry_id": "legacy-subentry",
                            "subentry_type": "conversation",
                            "title": "Casita Local",
                            "unique_id": None,
                        },
                        {
                            "data": {"model": "granite4.1:3b"},
                            "subentry_id": "chat-subentry",
                            "subentry_type": "conversation",
                            "title": "Casita Chat",
                            "unique_id": None,
                        },
                        {
                            "data": {"model": "granite4.1:3b"},
                            "subentry_id": "control-subentry",
                            "subentry_type": "conversation",
                            "title": "Casita Control",
                            "unique_id": None,
                        },
                        {
                            "data": {
                                "llm_hass_api": ["casita_workflows"],
                                "model": "granite4.1:3b",
                            },
                            "subentry_id": WORKFLOW_SUBENTRY_ID,
                            "subentry_type": "conversation",
                            "title": storage.WORKFLOW_SUBENTRY_TITLE,
                            "unique_id": None,
                        },
                    ],
                    "title": "http://172.16.25.26:11434",
                    "unique_id": None,
                    "version": 3,
                }
            ]
        }
    }


def entity_registry_document() -> dict:
    return {
        "data": {
            "entities": [
                {
                    "config_entry_id": DECK_ENTRY_ID,
                    "config_subentry_id": WORKFLOW_SUBENTRY_ID,
                    "entity_id": "conversation.casita_workflows",
                    "platform": "ollama",
                    "unique_id": WORKFLOW_SUBENTRY_ID,
                }
            ]
        }
    }


def device_registry_document() -> dict:
    return {
        "data": {
            "devices": [
                {
                    "config_entries": [DECK_ENTRY_ID],
                    "config_entries_subentries": {
                        DECK_ENTRY_ID: [WORKFLOW_SUBENTRY_ID]
                    },
                    "identifiers": [["ollama", WORKFLOW_SUBENTRY_ID]],
                    "name": storage.WORKFLOW_SUBENTRY_TITLE,
                }
            ]
        }
    }


class CasitaStorageMigrationTests(unittest.TestCase):
    def migrate(self, entries: dict, entities: dict, devices: dict) -> str:
        workflow_entry_id, workflow_subentry_id, previous_entry_ids = (
            storage.configure_entries(
                entries,
                "172.16.25.26",
                "granite4.1:3b",
                "http://192.168.1.6:11435",
                "qwen3:14b",
                300,
                8192,
            )
        )
        storage.configure_registries(
            entities,
            devices,
            workflow_entry_id,
            workflow_subentry_id,
            previous_entry_ids,
        )
        self.assertEqual(workflow_subentry_id, WORKFLOW_SUBENTRY_ID)
        return workflow_entry_id

    def test_workflow_agent_moves_without_changing_entity_id(self) -> None:
        entries = config_entries_document()
        entities = entity_registry_document()
        devices = device_registry_document()

        workflow_entry_id = self.migrate(entries, entities, devices)
        self.assertNotEqual(workflow_entry_id, DECK_ENTRY_ID)

        ollama_entries = [
            entry
            for entry in entries["data"]["entries"]
            if entry.get("domain") == "ollama"
        ]
        deck_entry = next(
            entry for entry in ollama_entries if entry["entry_id"] == DECK_ENTRY_ID
        )
        workflow_entry = next(
            entry
            for entry in ollama_entries
            if entry["entry_id"] == workflow_entry_id
        )

        self.assertEqual(deck_entry["data"]["url"], "http://172.16.25.26:11434")
        self.assertNotIn(
            storage.WORKFLOW_SUBENTRY_TITLE,
            {subentry["title"] for subentry in deck_entry["subentries"]},
        )
        self.assertEqual(workflow_entry["data"]["url"], "http://192.168.1.6:11435")
        workflow_subentry = workflow_entry["subentries"][0]
        self.assertEqual(workflow_subentry["subentry_id"], WORKFLOW_SUBENTRY_ID)
        self.assertEqual(workflow_subentry["data"]["model"], "qwen3:14b")
        self.assertEqual(workflow_subentry["data"]["keep_alive"], 300.0)
        self.assertEqual(workflow_subentry["data"]["num_ctx"], 8192.0)

        entity = entities["data"]["entities"][0]
        self.assertEqual(entity["entity_id"], "conversation.casita_workflows")
        self.assertEqual(entity["config_entry_id"], workflow_entry_id)
        self.assertEqual(entity["config_subentry_id"], WORKFLOW_SUBENTRY_ID)

        device = devices["data"]["devices"][0]
        self.assertEqual(device["config_entries"], [workflow_entry_id])
        self.assertEqual(
            device["config_entries_subentries"],
            {workflow_entry_id: [WORKFLOW_SUBENTRY_ID]},
        )

    def test_migration_is_idempotent(self) -> None:
        entries = config_entries_document()
        entities = entity_registry_document()
        devices = device_registry_document()
        workflow_entry_id = self.migrate(entries, entities, devices)
        migrated = copy.deepcopy((entries, entities, devices))

        second_workflow_entry_id = self.migrate(entries, entities, devices)

        self.assertEqual(second_workflow_entry_id, workflow_entry_id)
        self.assertEqual((entries, entities, devices), migrated)

    def test_rejects_shared_deck_and_workflow_route(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "must be isolated"):
            storage.configure_entries(
                config_entries_document(),
                "172.16.25.26",
                "granite4.1:3b",
                "http://172.16.25.26:11434/",
                "qwen3:14b",
                300,
                8192,
            )


if __name__ == "__main__":
    unittest.main()
