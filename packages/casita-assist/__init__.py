"""Casita's routed conversation agent and compact Home Assistant tool API."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import date, datetime
from enum import Enum
from http import HTTPStatus
import logging
import re
import time
from typing import Any, Literal, override

import voluptuous as vol
from hassil.recognize import RecognizeResult

from homeassistant.components import conversation, http
from homeassistant.components.conversation.const import DATA_COMPONENT
from homeassistant.const import MATCH_ALL
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv, llm
from homeassistant.helpers.typing import ConfigType
from homeassistant.util.json import JsonObjectType

DOMAIN = "casita_assist"
API_ID = "casita"
ROUTER_ENTITY_ID = "conversation.casita_router"
CHAT_AGENT = "conversation.casita_chat"
CONTROL_AGENT = "conversation.casita_control"
LEGACY_AGENT = "conversation.casita_local"
MODEL_NAME = "granite4.1:3b"
VOICE_NAME = "Kokoro · Heart"
EVENT_PROGRESS = "casita_assist_progress"

CONFIG_SCHEMA = cv.empty_config_schema(DOMAIN)

_LOGGER = logging.getLogger(__name__)

_CONTROL_PATTERNS = tuple(
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        r"\b(home|house|casita|room|light|lamp|fan|switch|thermostat|climate)\b",
        r"\b(weather|forecast|outside|humidity|sunrise|sunset)\b",
        r"\b(soc|s[ .-]?e[ .-]?m|security|alert|ddos|suricata|zeek|canary|greenbone)\b",
        r"\b(rack|server|host|fleet|deployment|backup|disk|storage|service probe)\b",
        r"\b(thornixos service|service status|services online|service latency|service reliability|service availability|service uptime|slowest service|services? (?:down|degraded|staged))\b",
        r"\b(anvil|atlas|casebook|courier|forge|herald|hound|identity|loom|proxmox)\b",
        r"\b(oracle|pixie|sieve|truenas|seaweed|pfsense|loki|prometheus|netbox|thehive|authentik)\b",
        r"\b(home assistant|ollama|granite|kokoro|open ?canary|owncast|jellyfin)\b",
        r"\b(thornflix|media|playing|pause|resume|skip|previous track|shopping list|grocery)\b",
        r"\b(tv|television|volume|mute|unmute|microphone|voice assistant|deck voice)\b",
        r"\b(jamie|anyone home|who is home|system status|what needs my attention)\b",
        r"\b(refresh|rescan|recheck)\b.*\b(service|services|status|telemetry)\b",
        r"\b(turn|set|start|stop|open|close|lock|unlock)\b.*\b(on|off|up|down|to|the)\b",
        r"\b(is|are|what(?:'s| is)|how)\b.*\b(on|off|online|offline|healthy|playing|full)\b",
    )
)

_FOLLOW_UP_PATTERN = re.compile(
    r"^(and |also |what about |how about |then |okay,? )|"
    r"\b(it|that|those|them|tomorrow|tonight|next|again)\b",
    re.IGNORECASE,
)

_MEDIA_PLAYERS = {
    "active": None,
    "chrome": "media_player.chrome",
    "chrome 2": "media_player.chrome_2",
    "firefox": "media_player.firefox",
    "lg tv": "media_player.lg_smart_tv",
    "tv": "media_player.lg_smart_tv",
    "ipad": "media_player.safari_ipad",
    "deck": "media_player.deck_voice_media_player",
}

_MEDIA_SERVICES = {
    "pause": "media_pause",
    "play": "media_play",
    "resume": "media_play",
    "stop": "media_stop",
    "next": "media_next_track",
    "previous": "media_previous_track",
}


def _json_value(value: Any, depth: int = 0) -> Any:
    """Return a small JSON-safe representation of a Home Assistant value."""
    if depth > 5:
        return None
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Enum):
        return _json_value(value.value, depth + 1)
    if isinstance(value, Mapping):
        return {
            str(key): _json_value(item, depth + 1)
            for key, item in list(value.items())[:32]
        }
    if isinstance(value, (list, tuple, set)):
        return [_json_value(item, depth + 1) for item in list(value)[:12]]
    return str(value)


def _state(
    hass: HomeAssistant,
    entity_id: str,
    attributes: tuple[str, ...] = (),
) -> JsonObjectType:
    """Return a compact state object."""
    state = hass.states.get(entity_id)
    if state is None:
        return {"entity_id": entity_id, "state": "unavailable"}

    result: JsonObjectType = {
        "entity_id": entity_id,
        "name": state.name,
        "state": state.state,
    }
    selected = {
        key: _json_value(state.attributes.get(key))
        for key in attributes
        if state.attributes.get(key) is not None
    }
    if selected:
        result["attributes"] = selected
    return result


def _emit_progress(hass: HomeAssistant, stage: str, **data: Any) -> None:
    """Publish a bounded progress event for the television UI."""
    hass.bus.async_fire(
        EVENT_PROGRESS,
        {
            "stage": stage,
            "model": MODEL_NAME,
            "voice": VOICE_NAME,
            **{key: _json_value(value) for key, value in data.items()},
        },
    )


class CasitaRouter(conversation.ConversationEntity):
    """Route open-ended requests to a no-tools chat or compact control agent."""

    _attr_name = "Casita Router"
    _attr_unique_id = "casita_router_v1"
    _attr_should_poll = False
    _attr_supports_streaming = True
    _attr_supported_features = conversation.ConversationEntityFeature.CONTROL

    def __init__(self) -> None:
        """Initialize the router."""
        self.entity_id = ROUTER_ENTITY_ID
        self._recent_routes: dict[str, tuple[str, float]] = {}

    @property
    @override
    def supported_languages(self) -> list[str] | Literal["*"]:
        """Return supported languages."""
        return MATCH_ALL

    def _route_for(self, text: str, conversation_id: str | None) -> str:
        normalized = " ".join(text.casefold().split())
        if any(pattern.search(normalized) for pattern in _CONTROL_PATTERNS):
            return "control"

        if (
            conversation_id
            and len(normalized.split()) <= 10
            and _FOLLOW_UP_PATTERN.search(normalized)
        ):
            previous = self._recent_routes.get(conversation_id)
            if previous and (time.monotonic() - previous[1]) < 180:
                return previous[0]

        return "chat"

    async def _matches_local_intent(
        self, user_input: conversation.ConversationInput
    ) -> bool:
        """Recognize deterministic HA commands skipped during LLM follow-ups."""
        local_agent = conversation.async_get_agent(
            self.hass, conversation.HOME_ASSISTANT_AGENT
        )
        if local_agent is None:
            return False

        recognize_trigger = getattr(
            local_agent, "async_recognize_sentence_trigger", None
        )
        if recognize_trigger is not None and await recognize_trigger(user_input):
            return True

        recognize_intent = getattr(local_agent, "async_recognize_intent", None)
        if recognize_intent is None:
            return False
        result = await recognize_intent(user_input, strict_intents_only=True)
        return isinstance(result, RecognizeResult)

    @override
    async def async_process(
        self, user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Route a conversation request without creating a duplicate chat log."""
        started = time.monotonic()
        if await self._matches_local_intent(user_input):
            route = "local"
            target = conversation.HOME_ASSISTANT_AGENT
            label = "Running local command"
            detail = "Using the deterministic Home Assistant response…"
        else:
            route = self._route_for(user_input.text, user_input.conversation_id)
            target = CONTROL_AGENT if route == "control" else CHAT_AGENT
            label = "Checking Casita" if route == "control" else "Thinking locally"
            detail = (
                "Selecting the smallest relevant home tools…"
                if route == "control"
                else "Using the fast conversation path…"
            )
        _emit_progress(
            self.hass,
            "routing",
            route=route,
            label=label,
            detail=detail,
        )

        available_target = conversation.async_get_agent(self.hass, target)
        if available_target is None:
            fallback = (
                LEGACY_AGENT
                if conversation.async_get_agent(self.hass, LEGACY_AGENT)
                else conversation.HOME_ASSISTANT_AGENT
            )
            _LOGGER.warning("Casita target %s unavailable; using %s", target, fallback)
            target = fallback
            route = "fallback"
            _emit_progress(
                self.hass,
                "fallback",
                route=route,
                label="Using fallback",
                detail="The preferred local route is unavailable.",
            )

        result = await conversation.async_converse(
            hass=self.hass,
            text=user_input.text,
            conversation_id=user_input.conversation_id,
            context=user_input.context,
            language=user_input.language,
            agent_id=target,
            device_id=user_input.device_id,
            satellite_id=user_input.satellite_id,
            extra_system_prompt=user_input.extra_system_prompt,
        )

        now = time.monotonic()
        for conversation_id in (user_input.conversation_id, result.conversation_id):
            if conversation_id:
                self._recent_routes[conversation_id] = (route, now)

        if len(self._recent_routes) > 64:
            cutoff = now - 300
            self._recent_routes = {
                key: value
                for key, value in self._recent_routes.items()
                if value[1] >= cutoff
            }

        _emit_progress(
            self.hass,
            "complete",
            route=route,
            label="Response ready",
            detail=f"{route.title()} route completed",
            elapsed_ms=round((time.monotonic() - started) * 1000),
        )
        return result


class CasitaTool(llm.Tool):
    """Base class that reports tool activity to the visual assistant."""

    def notify(self, hass: HomeAssistant) -> None:
        _emit_progress(
            hass,
            "tool",
            route="control",
            tool=self.name,
            label=self.description or self.name,
            detail="Reading live Home Assistant data…",
        )


class GetHomeStatus(CasitaTool):
    name = "GetHomeStatus"
    description = "Read presence, backup, sunlight, and ThornFlix summary."

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        return {
            "presence": _state(hass, "person.jamie_duddleston"),
            "backup": {
                "manager": _state(hass, "sensor.backup_backup_manager_state"),
                "last_successful": _state(
                    hass, "sensor.backup_last_successful_automatic_backup"
                ),
                "next_scheduled": _state(
                    hass, "sensor.backup_next_scheduled_automatic_backup"
                ),
            },
            "sun": {
                "next_rising": _state(hass, "sensor.sun_next_rising"),
                "next_setting": _state(hass, "sensor.sun_next_setting"),
            },
            "thornflix": _state(hass, "sensor.thornflix_active_clients"),
        }


class GetWeather(CasitaTool):
    name = "GetWeather"
    description = "Read current Casita weather and up to five forecast days."
    parameters = vol.Schema(
        {vol.Optional("days", default=3): vol.All(vol.Coerce(int), vol.Range(min=1, max=5))}
    )

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        entity_id = "weather.forecast_home"
        result: JsonObjectType = {
            "current": _state(
                hass,
                entity_id,
                (
                    "temperature",
                    "temperature_unit",
                    "humidity",
                    "pressure",
                    "wind_speed",
                    "wind_bearing",
                ),
            )
        }
        try:
            response = await hass.services.async_call(
                "weather",
                "get_forecasts",
                {"type": "daily"},
                target={"entity_id": entity_id},
                blocking=True,
                context=llm_context.context,
                return_response=True,
            )
            try:
                days = int(tool_input.tool_args.get("days", 3))
            except (TypeError, ValueError):
                days = 3
            days = max(1, min(5, days))
            forecast = (response or {}).get(entity_id, {}).get("forecast", [])
            result["forecast"] = _json_value(forecast[:days])
        except HomeAssistantError as err:
            result["forecast_error"] = str(err)
        return result


class GetSOCStatus(CasitaTool):
    name = "GetSOCStatus"
    description = "Read the bounded, read-only SOC operational and security summary."
    parameters = vol.Schema(
        {
            vol.Optional("detail", default="summary"): vol.In(
                ["summary", "actions", "fleet", "services", "security", "all"]
            )
        }
    )

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        state = hass.states.get("sensor.thornix_soc_status")
        if state is None:
            return {"status": "unavailable"}

        detail = tool_input.tool_args.get("detail", "summary")
        result: JsonObjectType = {
            "status": state.state,
            "generated_at": _json_value(state.attributes.get("generated_at")),
            "summary": _json_value(state.attributes.get("summary") or {}),
        }
        keys = (
            ("actions", "fleet", "services", "security", "deployment", "errors")
            if detail == "all"
            else (detail,)
        )
        for key in keys:
            value = state.attributes.get(key)
            if key == "actions" and isinstance(value, list):
                value = value[:5]
            if value is not None:
                result[key] = _json_value(value)
        return result


class GetServiceStatus(CasitaTool):
    name = "GetServiceStatus"
    description = (
        "Read current health, historical availability, latency, and SLO status "
        "for integrated ThornixOS services."
    )
    parameters = vol.Schema(
        {
            vol.Optional("service", default=""): str,
            vol.Optional("view", default="summary"): vol.In(
                ["summary", "attention", "slowest", "staged", "all"]
            ),
            vol.Optional("limit", default=5): vol.All(
                vol.Coerce(int), vol.Range(min=1, max=10)
            ),
        }
    )

    @staticmethod
    def _normalize(value: Any) -> str:
        return " ".join(re.sub(r"[^a-z0-9]+", " ", str(value).casefold()).split())

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        entries = []
        for state in hass.states.async_all():
            if not state.entity_id.startswith("sensor.thornix_service_"):
                continue
            if state.entity_id == "sensor.thornix_service_health":
                continue
            attributes = state.attributes
            entries.append(
                {
                    "id": str(
                        attributes.get("service_id")
                        or state.entity_id.split(".", maxsplit=1)[-1]
                    ),
                    "name": str(attributes.get("service_name") or state.name),
                    "role": str(attributes.get("role") or "ThornixOS service"),
                    "host": str(attributes.get("host") or ""),
                    "status": state.state,
                    "monitored": _json_value(attributes.get("monitored")),
                    "latency_seconds": _json_value(attributes.get("latency_seconds")),
                    "availability_percent": _json_value(
                        attributes.get("availability_percent")
                    ),
                    "latency_p95_seconds": _json_value(
                        attributes.get("latency_p95_seconds")
                    ),
                    "slo_status": str(attributes.get("slo_status") or "unknown"),
                    "reliability_window": str(
                        attributes.get("reliability_window") or "24h"
                    ),
                    "observed_at": _json_value(attributes.get("observed_at")),
                    "http_status": _json_value(attributes.get("http_status")),
                    "tls_days_remaining": _json_value(
                        attributes.get("tls_days_remaining")
                    ),
                    "url": str(attributes.get("launch_url") or ""),
                    "aliases": str(attributes.get("aliases") or ""),
                }
            )
        entries.sort(key=lambda item: (item["name"].casefold(), item["id"]))

        requested = self._normalize(tool_input.tool_args.get("service", ""))
        if requested:
            ranked = []
            for entry in entries:
                exact_terms = {
                    self._normalize(entry["id"]),
                    self._normalize(entry["name"]),
                    self._normalize(entry["host"]),
                    *(
                        self._normalize(alias)
                        for alias in entry["aliases"].split(",")
                        if alias.strip()
                    ),
                }
                haystack = " ".join(
                    self._normalize(entry[key])
                    for key in ("id", "name", "role", "host", "aliases")
                )
                if requested in exact_terms:
                    ranked.append((0, entry))
                elif requested in haystack or any(
                    term and term in requested for term in exact_terms
                ):
                    ranked.append((1, entry))
            ranked.sort(key=lambda item: (item[0], item[1]["name"].casefold()))
            if not ranked:
                return {
                    "query": requested,
                    "matches": [],
                    "known_services": [entry["name"] for entry in entries],
                }
            return {
                "query": requested,
                "matches": [entry for _, entry in ranked[:5]],
            }

        try:
            limit = max(1, min(10, int(tool_input.tool_args.get("limit", 5))))
        except (TypeError, ValueError):
            limit = 5
        view = str(tool_input.tool_args.get("view", "summary"))
        monitored = [entry for entry in entries if entry["status"] != "not_monitored"]
        attention = [
            entry
            for entry in monitored
            if entry["status"] != "healthy"
            or entry["slo_status"] in {"down", "breached", "at_risk"}
        ]
        staged = [entry for entry in entries if entry["status"] == "not_monitored"]

        def metric(item: dict[str, Any], key: str) -> float:
            try:
                return float(item.get(key) or -1)
            except (TypeError, ValueError):
                return -1

        slowest = sorted(
            monitored,
            key=lambda item: (
                -metric(item, "latency_p95_seconds"),
                -metric(item, "latency_seconds"),
                item["name"].casefold(),
            ),
        )
        selected = {
            "attention": attention,
            "slowest": slowest,
            "staged": staged,
            "all": entries,
        }.get(view, [])
        soc_state = hass.states.get("sensor.thornix_soc_status")
        return {
            "view": view,
            "generated_at": _json_value(
                soc_state.attributes.get("generated_at") if soc_state else None
            ),
            "total": len(entries),
            "monitored": len(monitored),
            "healthy": sum(1 for entry in monitored if entry["status"] == "healthy"),
            "slo_met": sum(1 for entry in monitored if entry["slo_status"] == "met"),
            "attention_count": len(attention),
            "staged_count": len(staged),
            "results": selected[:limit],
            "services": [
                {
                    "id": entry["id"],
                    "name": entry["name"],
                    "role": entry["role"],
                    "status": entry["status"],
                }
                for entry in entries
            ],
        }


class RefreshServiceStatus(CasitaTool):
    name = "RefreshServiceStatus"
    description = (
        "Explicitly refresh the bounded SOC service snapshot and Sony TV display."
    )

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        await hass.services.async_call(
            "homeassistant",
            "update_entity",
            {},
            target={"entity_id": "sensor.thornix_soc_status"},
            blocking=True,
            context=llm_context.context,
        )
        display_synced = True
        try:
            await hass.services.async_call(
                "automation",
                "trigger",
                {"skip_condition": True},
                target={"entity_id": "automation.deck_voice_visual_data_sync"},
                blocking=True,
                context=llm_context.context,
            )
        except HomeAssistantError:
            display_synced = False
        state = hass.states.get("sensor.thornix_soc_status")
        services = state.attributes.get("services", {}) if state else {}
        return {
            "refreshed": state is not None,
            "display_synced": display_synced,
            "status": state.state if state else "unavailable",
            "generated_at": _json_value(
                state.attributes.get("generated_at") if state else None
            ),
            "checked": _json_value(services.get("checked")),
            "healthy": _json_value(services.get("healthy")),
            "slo_attention": _json_value(services.get("slo_attention") or []),
        }


class GetRackStatus(CasitaTool):
    name = "GetRackStatus"
    description = "Read network rack temperature, humidity, and sensor battery."

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        return {
            "temperature": _state(
                hass,
                "sensor.h5179_f81a_temperature",
                ("unit_of_measurement",),
            ),
            "humidity": _state(
                hass,
                "sensor.h5179_f81a_humidity",
                ("unit_of_measurement",),
            ),
            "battery": _state(
                hass,
                "sensor.h5179_f81a_battery",
                ("unit_of_measurement",),
            ),
        }


class GetVoiceHealth(CasitaTool):
    name = "GetVoiceHealth"
    description = "Read microphone, satellite, local model, and natural voice health."

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        return {
            "satellite": _state(
                hass,
                "sensor.deck_voice_health",
                (
                    "connected",
                    "streaming",
                    "voice_state",
                    "last_event_age",
                    "recovery_count",
                    "recovery_reason",
                    "audio",
                ),
            ),
            "model": _state(hass, "sensor.deck_conversation_model"),
            "natural_voice": _state(
                hass,
                "sensor.deck_natural_voice",
                ("voice", "synthesis_count", "last_synthesis_seconds"),
            ),
            "muted": _state(hass, "switch.deck_voice_mute"),
        }


class GetMediaStatus(CasitaTool):
    name = "GetMediaStatus"
    description = "Read the safe, exposed media players and what is playing."

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        players = []
        for name, entity_id in _MEDIA_PLAYERS.items():
            if name == "active" or entity_id is None:
                continue
            players.append(
                {
                    "player": name,
                    **_state(
                        hass,
                        entity_id,
                        ("media_title", "media_artist", "volume_level", "is_volume_muted"),
                    ),
                }
            )
        return {"players": players}


class ControlMedia(CasitaTool):
    name = "ControlMedia"
    description = "Pause, play, stop, skip, or go back on an exposed media player."
    parameters = vol.Schema(
        {
            vol.Required("action"): vol.In(list(_MEDIA_SERVICES)),
            vol.Optional("player", default="active"): vol.In(list(_MEDIA_PLAYERS)),
        }
    )

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        action = tool_input.tool_args["action"]
        player = tool_input.tool_args.get("player", "active")
        entity_id = _MEDIA_PLAYERS[player]
        if entity_id is None:
            preferred_states = (
                ("paused",) if action in {"play", "resume"} else ("playing", "paused")
            )
            for candidate in _MEDIA_PLAYERS.values():
                if candidate is None:
                    continue
                candidate_state = hass.states.get(candidate)
                if candidate_state and candidate_state.state in preferred_states:
                    entity_id = candidate
                    break
        if entity_id is None:
            return {"success": False, "error": "No matching active media player"}

        await hass.services.async_call(
            "media_player",
            _MEDIA_SERVICES[action],
            {},
            target={"entity_id": entity_id},
            blocking=True,
            context=llm_context.context,
        )
        return {"success": True, "action": action, "entity_id": entity_id}


class ShoppingList(CasitaTool):
    name = "ShoppingList"
    description = "Read, add, complete, or remove an item from the shopping list."
    parameters = vol.Schema(
        {
            vol.Required("action"): vol.In(["read", "add", "complete", "remove"]),
            vol.Optional("item"): str,
        }
    )

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        action = tool_input.tool_args["action"]
        item = str(tool_input.tool_args.get("item") or "").strip()
        if action == "read":
            response = await hass.services.async_call(
                "todo",
                "get_items",
                {"status": ["needs_action"]},
                target={"entity_id": "todo.shopping_list"},
                blocking=True,
                context=llm_context.context,
                return_response=True,
            )
            items = (response or {}).get("todo.shopping_list", {}).get("items", [])
            return {
                "items": [
                    entry.get("summary") or entry.get("name")
                    for entry in items[:20]
                ]
            }

        if not item:
            raise HomeAssistantError(f"An item is required to {action} the list")
        service = {
            "add": "add_item",
            "complete": "complete_item",
            "remove": "remove_item",
        }[action]
        await hass.services.async_call(
            "shopping_list",
            service,
            {"name": item},
            blocking=True,
            context=llm_context.context,
        )
        return {"success": True, "action": action, "item": item}


class SetTVAudio(CasitaTool):
    name = "SetTVAudio"
    description = "Safely change the Deck HDMI television volume or mute state."
    parameters = vol.Schema(
        {
            vol.Required("action"): vol.In(
                ["volume_up", "volume_down", "mute", "unmute", "set"]
            ),
            vol.Optional("level"): vol.All(
                vol.Coerce(float), vol.Range(min=0, max=100)
            ),
        }
    )

    @override
    async def async_call(self, hass, tool_input, llm_context) -> JsonObjectType:
        self.notify(hass)
        action = tool_input.tool_args["action"]
        if action == "set" and "level" not in tool_input.tool_args:
            raise HomeAssistantError("A level from 0 to 100 is required")
        deck_action = {
            "volume_up": "volume-up",
            "volume_down": "volume-down",
            "mute": "volume-mute",
            "unmute": "volume-unmute",
            "set": "volume-set",
        }[action]
        data: dict[str, Any] = {"action": deck_action}
        if action == "set":
            data["value"] = tool_input.tool_args["level"]
        await hass.services.async_call(
            "rest_command",
            "deck_voice_action",
            data,
            blocking=True,
            context=llm_context.context,
        )
        return {"success": True, "action": action, "level": data.get("value")}


class CasitaAPI(llm.API):
    """Compact, safe tool surface for the Deck-sized local model."""

    @override
    async def async_get_api_instance(
        self, llm_context: llm.LLMContext
    ) -> llm.APIInstance:
        return llm.APIInstance(
            api=self,
            api_prompt=(
                "Use these compact local tools for all current home, weather, media, "
                "voice, rack, shopping-list, ThornixOS service, and SOC questions. "
                "Call a read tool before "
                "answering current-state questions; never guess live values. Only call a "
                "control or refresh tool after an explicit user request. Service health "
                "includes current reachability plus bounded availability and latency SLOs. "
                "SOC tools are read-only. "
                "Locks, doors, alarms, security controls, deletion, and administrative "
                "actions are intentionally unavailable. Report tool failures honestly."
            ),
            llm_context=llm_context,
            tools=[
                GetHomeStatus(),
                GetWeather(),
                GetSOCStatus(),
                GetServiceStatus(),
                RefreshServiceStatus(),
                GetRackStatus(),
                GetVoiceHealth(),
                GetMediaStatus(),
                ControlMedia(),
                ShoppingList(),
                SetTVAudio(),
            ],
        )


class CasitaHealthView(http.HomeAssistantView):
    """Expose a narrow unauthenticated health view for the SOC."""

    url = "/api/casita/health"
    name = "api:casita:health"
    requires_auth = False

    async def get(self, request):
        hass = request.app[http.KEY_HASS]
        entities = {
            entity_id: hass.states.get(entity_id)
            for entity_id in (ROUTER_ENTITY_ID, CHAT_AGENT, CONTROL_AGENT)
        }
        ready = {
            entity_id: state is not None and state.state not in {"unavailable", "unknown"}
            for entity_id, state in entities.items()
        }
        healthy = all(ready.values())
        return self.json(
            {
                "status": "healthy" if healthy else "degraded",
                "router": ready[ROUTER_ENTITY_ID],
                "chat_agent": ready[CHAT_AGENT],
                "control_agent": ready[CONTROL_AGENT],
                "model": MODEL_NAME,
                "voice": VOICE_NAME,
            },
            status_code=(HTTPStatus.OK if healthy else HTTPStatus.SERVICE_UNAVAILABLE),
        )


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    """Set up the compact API and router entity."""
    unregister_api = llm.async_register_api(
        hass,
        CasitaAPI(hass=hass, id=API_ID, name="Casita safe local tools"),
    )
    router = CasitaRouter()
    component = hass.data[DATA_COMPONENT]
    await component.async_add_entities([router])
    hass.data[DOMAIN] = {
        "router": router,
        "unregister_api": unregister_api,
    }
    hass.http.register_view(CasitaHealthView)
    _LOGGER.info("Casita router and compact LLM API are ready")
    return True
