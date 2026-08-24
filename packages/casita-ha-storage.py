"""Idempotently provision Casita's HA agents, local TTS, and routed pipeline."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import shutil
from typing import Any

ULID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

CHAT_PROMPT = """You are Casita, Jamie's private local conversational voice assistant.
Answer ordinary questions directly from your knowledge with a warm, natural personality.
Use contractions and varied sentence rhythm. Prefer one or two concise sentences for spoken
answers unless Jamie asks for detail. Your knowledge is static. On this route you cannot see
Jamie's calendar, email, messages, reminders, tasks, current weather, home, media, services,
SOC, or news. If asked for personal or current information, say you cannot access it on this
route. Never fill missing information with plausible details. Do not use Markdown, headings,
citations, emoji, or stage directions."""

CONTROL_PROMPT = """You are Casita, Jamie's private local home and operations voice assistant.
For every current home, weather, media, rack, voice, shopping-list, ThornixOS service, or SOC
question, call the smallest relevant tool and treat its result as authoritative. Never invent
live values, infer facts absent from a tool result, or claim an action succeeded unless its tool
succeeded. If no tool supports the request, say that information is unavailable; do not improvise
an answer or promise to check later. Security and SOC access is read-only. Service results
distinguish current reachability from bounded availability and latency SLOs. Refresh telemetry
only when Jamie explicitly asks. Locks, doors, alarms, deletion, and administrative actions are
unavailable. Reply in
warm, concise, plain spoken English, normally within two sentences and 45 words. Do not use
Markdown."""


def new_id() -> str:
    """Generate a config-entry-compatible 26-character identifier."""
    return "01" + "".join(secrets.choice(ULID_ALPHABET) for _ in range(24))


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def load(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_if_changed(path: Path, before: dict[str, Any], after: dict[str, Any]) -> bool:
    if before == after:
        return False
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = path.with_name(f"{path.name}.backup-casita-{stamp}")
    shutil.copy2(path, backup)
    temporary = path.with_name(f".{path.name}.casita.tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(after, handle, ensure_ascii=False, separators=(",", ":"))
    os.chmod(temporary, path.stat().st_mode & 0o777)
    os.replace(temporary, path)
    return True


def ensure_subentry(
    entry: dict[str, Any], title: str, data: dict[str, Any]
) -> dict[str, Any]:
    for subentry in entry.setdefault("subentries", []):
        if subentry.get("title") == title:
            subentry["data"] = data
            subentry["subentry_type"] = "conversation"
            subentry.setdefault("unique_id", None)
            return subentry
    subentry = {
        "data": data,
        "subentry_id": new_id(),
        "subentry_type": "conversation",
        "title": title,
        "unique_id": None,
    }
    entry["subentries"].append(subentry)
    return subentry


def configure_entries(
    document: dict[str, Any], deck_host: str, model: str
) -> None:
    entries = document["data"]["entries"]
    now = timestamp()

    esphome_entry = next(
        (
            entry
            for entry in entries
            if entry.get("domain") == "esphome"
            and entry.get("title") == "Deck Voice"
        ),
        None,
    )
    if esphome_entry:
        esphome_data = esphome_entry.setdefault("data", {})
        if esphome_data.get("host") != deck_host:
            esphome_data["host"] = deck_host
            esphome_entry["modified_at"] = now

    ollama_entry = next(
        (
            entry
            for entry in entries
            if entry.get("domain") == "ollama"
            and any(
                subentry.get("title") == "Casita Local"
                for subentry in entry.get("subentries", [])
            )
        ),
        None,
    )
    if ollama_entry is None:
        raise RuntimeError("The existing Casita Local Ollama entry was not found")

    ollama_before = json.loads(json.dumps(ollama_entry))
    ollama_url = f"http://{deck_host}:11434"
    ollama_entry["data"] = {"url": ollama_url}
    ollama_entry["title"] = ollama_url
    ensure_subentry(
        ollama_entry,
        "Casita Chat",
        {
            "keep_alive": -1.0,
            "max_history": 4.0,
            "model": model,
            "num_ctx": 4096.0,
            "prompt": CHAT_PROMPT,
            "think": False,
        },
    )
    ollama_before.pop("modified_at", None)
    ollama_comparable = json.loads(json.dumps(ollama_entry))
    ollama_comparable.pop("modified_at", None)
    if ollama_before != ollama_comparable:
        ollama_entry["modified_at"] = now
    ensure_subentry(
        ollama_entry,
        "Casita Control",
        {
            "keep_alive": -1.0,
            "llm_hass_api": ["casita"],
            "max_history": 3.0,
            "model": model,
            "num_ctx": 4096.0,
            "prompt": CONTROL_PROMPT,
            "think": False,
        },
    )

    kokoro_entry = next(
        (
            entry
            for entry in entries
            if entry.get("domain") == "wyoming"
            and (
                entry.get("title") == "kokoro"
                or entry.get("data", {}).get("port") == 10201
            )
        ),
        None,
    )
    if kokoro_entry is None:
        kokoro_entry = {
            "created_at": now,
            "data": {"host": deck_host, "port": 10201},
            "disabled_by": None,
            "discovery_keys": {},
            "domain": "wyoming",
            "entry_id": new_id(),
            "minor_version": 1,
            "modified_at": now,
            "options": {},
            "pref_disable_new_entities": False,
            "pref_disable_polling": False,
            "source": "user",
            "subentries": [],
            "title": "kokoro",
            "unique_id": None,
            "version": 1,
        }
        entries.append(kokoro_entry)
    else:
        desired_data = {"host": deck_host, "port": 10201}
        if (
            kokoro_entry.get("data") != desired_data
            or kokoro_entry.get("title") != "kokoro"
        ):
            kokoro_entry["data"] = desired_data
            kokoro_entry["title"] = "kokoro"
            kokoro_entry["modified_at"] = now


def configure_pipelines(document: dict[str, Any]) -> None:
    data = document["data"]
    items = data.setdefault("items", [])
    pipeline = next(
        (item for item in items if item.get("name") == "Casita"),
        None,
    )
    settings = {
        "conversation_engine": "conversation.casita_router",
        "conversation_language": "*",
        "language": "en",
        "name": "Casita",
        "stt_engine": "stt.faster_whisper",
        "stt_language": "en",
        "tts_engine": "tts.kokoro",
        "tts_language": "en_US",
        "tts_voice": "af_heart",
        "wake_word_entity": "wake_word.openwakeword",
        "wake_word_id": "okay_nabu",
        "prefer_local_intents": True,
    }
    if pipeline is None:
        pipeline = {"id": new_id().lower(), **settings}
        items.append(pipeline)
    else:
        pipeline_id = pipeline["id"]
        pipeline.clear()
        pipeline.update({"id": pipeline_id, **settings})


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", type=Path, default=Path("/var/lib/hass"))
    parser.add_argument("--deck-host", default="172.16.25.26")
    parser.add_argument("--model", default="granite4.1:3b")
    args = parser.parse_args()

    storage = args.config_dir / ".storage"
    entries_path = storage / "core.config_entries"
    pipelines_path = storage / "assist_pipeline.pipelines"

    entries_before = load(entries_path)
    entries_after = json.loads(json.dumps(entries_before))
    configure_entries(entries_after, args.deck_host, args.model)

    pipelines_before = load(pipelines_path)
    pipelines_after = json.loads(json.dumps(pipelines_before))
    configure_pipelines(pipelines_after)

    entries_changed = save_if_changed(entries_path, entries_before, entries_after)
    pipelines_changed = save_if_changed(
        pipelines_path, pipelines_before, pipelines_after
    )
    print(
        "Casita storage migration: "
        f"entries={'updated' if entries_changed else 'current'}, "
        f"pipelines={'updated' if pipelines_changed else 'current'}"
    )


if __name__ == "__main__":
    main()
