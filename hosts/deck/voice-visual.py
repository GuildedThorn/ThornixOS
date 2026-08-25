import argparse
import array
import ipaddress
import json
import math
import os
import queue
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import websocket


BIND_HOST = "0.0.0.0"
LOOPBACK_HOST = "127.0.0.1"
PORT = 10701
HOME_ASSISTANT_HOST = "172.16.25.2"
SOC_HOST = "172.16.25.51"
HEALTH_CLIENTS = {HOME_ASSISTANT_HOST, SOC_HOST}
EVENT_URL = f"http://{LOOPBACK_HOST}:{PORT}/api/event"
LVA_PERIPHERAL_URL = "ws://127.0.0.1:6055"
MAX_BODY = 65536
RECONNECT_COOLDOWN = 4.0
PAGE = ""
HOME_STATE_FILE = None
RECONNECT_LOCK = threading.Lock()
LAST_RECONNECT = 0.0


def is_loopback(address):
    try:
        return ipaddress.ip_address(address).is_loopback
    except ValueError:
        return False


def sanitize(value, depth=0):
    if depth > 5:
        return None
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return value[:512]
    if isinstance(value, list):
        return [sanitize(item, depth + 1) for item in value[:32]]
    if isinstance(value, dict):
        return {
            str(key)[:64]: sanitize(item, depth + 1)
            for key, item in list(value.items())[:64]
        }
    return str(value)[:512]


class StateHub:
    def __init__(self):
        started_at = time.time()
        self.lock = threading.Lock()
        self.clients = set()
        self.voice_revision = 0
        self.connection_revision = 0
        self.state = {
            "status": "starting",
            "label": "Starting",
            "transcript": "",
            "response": "",
            "detail": "Connecting to Home Assistant…",
            "assistant_stage": "",
            "route": "",
            "tool": "",
            "model": "",
            "voice": "",
            "elapsed_ms": None,
            "connected": False,
            "streaming": False,
            "muted": False,
            "updated": started_at,
            "started_at": started_at,
            "last_event": started_at,
            "recovery_count": 0,
            "last_recovery": 0,
            "recovery_reason": "",
            "health": {
                "pipewire": False,
                "capture": False,
                "audio_level": 0,
                "audio_updated": 0,
                "output_volume": None,
                "output_muted": False,
            },
            "home_updated": 0,
            "home": {},
            "timer": None,
        }

    def snapshot(self):
        with self.lock:
            return dict(self.state)

    def subscribe(self):
        client = queue.Queue(maxsize=48)
        with self.lock:
            self.clients.add(client)
            current = dict(self.state)
        client.put_nowait(("state", current))
        return client

    def unsubscribe(self, client):
        with self.lock:
            self.clients.discard(client)

    def broadcast(self, event, payload):
        with self.lock:
            clients = list(self.clients)
        for client in clients:
            try:
                client.put_nowait((event, payload))
            except queue.Full:
                try:
                    client.get_nowait()
                    client.put_nowait((event, payload))
                except (queue.Empty, queue.Full):
                    pass

    def set_voice(self, **changes):
        with self.lock:
            self.voice_revision += 1
            revision = self.voice_revision
            if "connected" in changes:
                self.connection_revision += 1
            self.state.update(changes)
            self.state["updated"] = time.time()
            self.state["last_event"] = self.state["updated"]
            snapshot = dict(self.state)
        self.broadcast("state", snapshot)
        return revision

    def set_home(self, home, persist=True):
        with self.lock:
            self.state["home"] = home
            self.state["home_updated"] = time.time()
            snapshot = dict(self.state)
        if persist:
            persist_home(home)
        self.broadcast("state", snapshot)

    def set_assistant(self, progress):
        """Update the routed-assistant metadata without racing the audio UI."""
        stage = str(progress.get("stage") or "thinking")[:32]
        with self.lock:
            self.state.update(
                {
                    "assistant_stage": stage,
                    "route": str(progress.get("route") or "")[:32],
                    "tool": str(progress.get("tool") or "")[:64],
                    "model": str(progress.get("model") or "")[:64],
                    "voice": str(progress.get("voice") or "")[:64],
                    "elapsed_ms": progress.get("elapsed_ms"),
                }
            )
            # Progress delivery is asynchronous. Only change the conversational
            # status while we are still thinking, never after TTS has started.
            if stage in {"routing", "tool", "fallback"} and self.state.get(
                "status"
            ) == "thinking":
                label = str(progress.get("label") or "")[:96]
                detail = str(progress.get("detail") or "")[:256]
                if label:
                    self.state["label"] = label
                if detail:
                    self.state["detail"] = detail
            self.state["updated"] = time.time()
            snapshot = dict(self.state)
        self.broadcast("state", snapshot)

    def set_health(self, **changes):
        with self.lock:
            health = dict(self.state["health"])
            changed = any(health.get(key) != value for key, value in changes.items())
            if not changed:
                return
            health.update(changes)
            self.state["health"] = health
            snapshot = dict(self.state)
        self.broadcast("state", snapshot)

    def set_audio_level(self, level, capture=True):
        now = time.time()
        with self.lock:
            health = dict(self.state["health"])
            health.update(
                {
                    "capture": capture,
                    "audio_level": level,
                    "audio_updated": now,
                }
            )
            self.state["health"] = health
        self.broadcast("level", level)

    def note_recovery(self, reason):
        with self.lock:
            self.state["recovery_count"] += 1
            self.state["last_recovery"] = time.time()
            self.state["recovery_reason"] = reason
            snapshot = dict(self.state)
        self.broadcast("state", snapshot)

    def health_snapshot(self):
        with self.lock:
            state = dict(self.state)
            health = dict(state.get("health") or {})
        connected = bool(state.get("connected"))
        streaming = bool(state.get("streaming"))
        pipewire = bool(health.get("pipewire"))
        if connected and streaming and pipewire:
            status = "healthy"
        elif state.get("status") in {"starting", "offline"}:
            status = "recovering"
        else:
            status = "degraded"
        return {
            "status": status,
            "connected": connected,
            "streaming": streaming,
            "voice_state": state.get("status", "unknown"),
            "last_event": state.get("last_event", 0),
            "last_event_age": max(0, time.time() - state.get("last_event", 0)),
            "uptime_seconds": max(
                0, time.time() - state.get("started_at", time.time())
            ),
            "recovery_count": state.get("recovery_count", 0),
            "last_recovery": state.get("last_recovery", 0),
            "recovery_reason": state.get("recovery_reason", ""),
            "audio": health,
        }

    def idle_later(self, revision, delay=10):
        def reset():
            with self.lock:
                if self.voice_revision != revision:
                    return
            self.set_voice(
                status="idle",
                label="Ready",
                transcript="",
                response="",
                detail="",
                assistant_stage="",
                route="",
                tool="",
                elapsed_ms=None,
            )

        timer = threading.Timer(delay, reset)
        timer.daemon = True
        timer.start()

    def recover_later(self, connection_revision, delay=18):
        def recover():
            with self.lock:
                if (
                    self.connection_revision != connection_revision
                    or self.state["connected"]
                ):
                    return
            self.set_voice(
                status="starting",
                label="Reconnecting",
                detail="Refreshing the voice stream…",
            )
            reconnect_voice(reason="server disconnected")

        timer = threading.Timer(delay, recover)
        timer.daemon = True
        timer.start()

    def recover_error_later(self, revision, delay=1.5):
        """Restart a pipeline that did not resume after an error event."""

        def recover():
            with self.lock:
                if self.voice_revision != revision or self.state["streaming"]:
                    return
            self.set_voice(
                status="starting",
                label="Recovering microphone",
                connected=False,
                streaming=False,
                transcript="",
                response="",
                detail="Resetting the Assist audio stream…",
            )
            reconnect_voice(reason="pipeline error")

        timer = threading.Timer(delay, recover)
        timer.daemon = True
        timer.start()

    def recover_stream_later(self, revision, delay=12):
        """Recover a connection that never resumes its microphone stream."""

        def recover():
            with self.lock:
                if (
                    self.voice_revision != revision
                    or self.state["streaming"]
                    or not self.state["connected"]
                ):
                    return
            self.set_voice(
                status="starting",
                label="Recovering microphone",
                connected=False,
                detail="The audio stream stalled. Establishing a fresh connection…",
            )
            reconnect_voice(reason="stream stalled")

        timer = threading.Timer(delay, recover)
        timer.daemon = True
        timer.start()

    def event(self, name, payload):
        text, data = decode_payload(payload)

        if name == "startup":
            self.set_voice(
                status="starting",
                label="Starting",
                connected=False,
                streaming=False,
                detail="Connecting to Home Assistant…",
            )
        elif name == "connected":
            revision = self.set_voice(
                status="idle",
                label="Ready",
                connected=True,
                streaming=False,
                detail="",
            )
            self.recover_stream_later(revision)
        elif name == "disconnected":
            self.set_voice(
                status="offline",
                label="Home Assistant offline",
                connected=False,
                streaming=False,
                detail="The voice stream will reconnect automatically.",
            )
            with self.lock:
                connection_revision = self.connection_revision
            self.recover_later(connection_revision)
        elif name == "streaming-start":
            self.set_voice(
                status="idle",
                label="Ready",
                connected=True,
                streaming=True,
                detail="",
            )
        elif name == "streaming-stop":
            revision = self.set_voice(
                status="paused",
                label="Paused",
                streaming=False,
                detail="Microphone stream paused",
            )
            self.recover_stream_later(revision, delay=10)
        elif name == "detect":
            if self.snapshot()["status"] in {"starting", "offline", "paused"}:
                self.set_voice(
                    status="idle",
                    label="Ready",
                    connected=True,
                    detail="",
                )
        elif name in {"detection", "stt-start"}:
            wake_display()
            self.set_voice(
                status="listening",
                label="Listening",
                transcript="",
                response="",
                detail="Go ahead…",
                assistant_stage="",
                route="",
                tool="",
                elapsed_ms=None,
                connected=True,
            )
        elif name == "stt-stop":
            self.set_voice(
                status="thinking",
                label="Thinking",
                detail="Understanding your request…",
            )
        elif name == "transcript":
            self.set_voice(
                status="thinking",
                label="Thinking",
                transcript=text,
                response="",
                detail="Asking Home Assistant…",
            )
        elif name in {"synthesize", "tts-start", "tts-stop"}:
            changes = {"status": "speaking", "label": "Responding", "detail": ""}
            if name == "synthesize" and text:
                changes["response"] = text
            self.set_voice(**changes)
        elif name == "played":
            revision = self.set_voice(status="done", label="Done", detail="")
            self.idle_later(revision, 14)
        elif name == "error":
            no_text = "no text recognized" in text.lower()
            revision = self.set_voice(
                status="error",
                label="I didn't catch that" if no_text else "Something went wrong",
                streaming=False,
                response="",
                detail=(
                    "Try speaking a little closer to the Deck."
                    if no_text
                    else text or "Home Assistant could not complete the request."
                ),
            )
            # Compatibility path for the retired event-hook transport. A fresh
            # streaming-start event cancels this recovery; otherwise restart
            # the local voice service and establish a clean pipeline.
            self.recover_error_later(revision)
        elif name == "timer-started":
            seconds = numeric_seconds(data)
            timer = {
                "id": str(data.get("id", "")),
                "name": str(data.get("name") or "Timer"),
                "total_seconds": seconds,
                "ends_at": time.time() + seconds,
                "active": True,
                "finished": False,
            }
            revision = self.set_voice(
                status="done",
                label="Timer set",
                detail=timer_summary(seconds, "Timer started"),
                timer=timer,
            )
            self.idle_later(revision, 10)
        elif name == "timer-updated":
            seconds = numeric_seconds(data)
            previous = self.snapshot().get("timer") or {}
            active = bool(data.get("is_active", True))
            timer = {
                "id": str(data.get("id") or previous.get("id") or ""),
                "name": str(previous.get("name") or "Timer"),
                "total_seconds": seconds,
                "ends_at": time.time() + seconds if active else None,
                "active": active,
                "finished": False,
            }
            revision = self.set_voice(
                status="done",
                label="Timer updated",
                detail=timer_summary(seconds, "Timer updated"),
                timer=timer,
            )
            self.idle_later(revision, 10)
        elif name == "timer-cancelled":
            revision = self.set_voice(
                status="done",
                label="Timer cancelled",
                detail="",
                timer=None,
            )
            self.idle_later(revision, 8)
        elif name == "timer-finished":
            previous = self.snapshot().get("timer") or {}
            timer = {
                "id": str(data.get("id") or previous.get("id") or ""),
                "name": str(previous.get("name") or "Timer"),
                "total_seconds": 0,
                "ends_at": None,
                "active": False,
                "finished": True,
            }
            self.set_voice(
                status="speaking",
                label="Timer finished",
                detail="Time is up",
                timer=timer,
            )

    def lva_event(self, name, data):
        """Translate Linux Voice Assistant peripheral events for the TV UI."""

        data = data if isinstance(data, dict) else {}
        payload = json.dumps({"data": data}, ensure_ascii=False)

        if name == "snapshot":
            connected = bool(data.get("ha_connected"))
            self.set_voice(
                status="idle" if connected else "offline",
                label="Ready" if connected else "Home Assistant offline",
                connected=connected,
                streaming=True,
                muted=bool(data.get("muted")),
                transcript=str(data.get("last_stt_text") or ""),
                response=str(data.get("last_tts_text") or ""),
                detail="" if connected else "Waiting for Home Assistant…",
            )
        elif name == "zeroconf":
            connected = data.get("status") == "connected"
            self.set_voice(
                status="idle" if connected else "starting",
                label="Ready" if connected else "Connecting",
                connected=connected,
                streaming=True,
                detail="" if connected else "Connecting to Home Assistant…",
            )
        elif name == "disconnected":
            self.set_voice(
                status="offline",
                label="Home Assistant offline",
                connected=False,
                streaming=True,
                detail="The assistant will reconnect automatically.",
            )
        elif name == "wake_word_detected":
            self.event("detection", "")
        elif name == "listening":
            self.event("stt-start", "")
        elif name == "stt_text":
            self.event("transcript", payload)
        elif name == "thinking":
            self.event("stt-stop", "")
        elif name == "tts_text":
            self.event("synthesize", payload)
        elif name == "tts_speaking":
            self.event("tts-start", "")
        elif name == "tts_finished":
            self.event("played", "")
        elif name == "idle":
            self.set_voice(
                status="idle",
                label="Ready",
                connected=True,
                streaming=True,
                detail="",
            )
        elif name == "pipeline_error":
            reason = str(
                data.get("reason")
                or "Home Assistant could not complete the request."
            )
            revision = self.set_voice(
                status="error",
                label=(
                    "I didn't catch that"
                    if "no text" in reason.lower()
                    else "Something went wrong"
                ),
                connected=True,
                streaming=True,
                response="",
                detail=reason,
            )
            # LVA restores its local wake-word loop after an error, so the TV
            # only needs to reset visually; no service restart is required.
            self.idle_later(revision, 6)
        elif name in {"timer_ticking", "timer_updated"}:
            total = max(0, int(data.get("total_seconds") or 0))
            remaining = max(0, int(data.get("seconds_left") or 0))
            timer = {
                "id": str(data.get("id") or ""),
                "name": str(data.get("name") or "Timer"),
                "total_seconds": total,
                "ends_at": time.time() + remaining,
                "active": True,
                "finished": False,
            }
            self.set_voice(
                status="idle",
                label="Ready",
                connected=True,
                streaming=True,
                timer=timer,
            )
        elif name == "timer_ringing":
            timer = {
                "id": str(data.get("id") or ""),
                "name": str(data.get("name") or "Timer"),
                "total_seconds": max(0, int(data.get("total_seconds") or 0)),
                "ends_at": None,
                "active": False,
                "finished": True,
            }
            self.set_voice(
                status="speaking",
                label="Timer finished",
                connected=True,
                streaming=True,
                detail="Time is up",
                timer=timer,
            )
        elif name == "muted":
            muted = bool(data.get("muted"))
            self.set_voice(
                status="paused" if muted else "idle",
                label="Microphone muted" if muted else "Ready",
                connected=True,
                streaming=True,
                muted=muted,
                detail="Say or use Home Assistant to unmute" if muted else "",
            )
        elif name == "volume_changed":
            try:
                volume = round(float(data.get("volume")) * 100)
            except (TypeError, ValueError):
                return
            self.set_health(output_volume=volume)
        elif name == "volume_muted":
            self.set_health(output_muted=bool(data.get("muted")))
        elif name == "media_player_playing":
            self.set_voice(
                status="speaking",
                label="Media playing",
                connected=True,
                streaming=True,
                detail="",
            )


def decode_payload(payload):
    if not payload:
        return "", {}
    try:
        parsed = json.loads(payload)
    except json.JSONDecodeError:
        return payload.strip(), {}
    if not isinstance(parsed, dict):
        return str(parsed), {}
    data = parsed.get("data")
    if not isinstance(data, dict):
        data = parsed
    for key in ("text", "name", "message"):
        value = data.get(key)
        if value:
            return str(value), data
    return "", data


def numeric_seconds(data):
    seconds = data.get("total_seconds", data.get("seconds", 0))
    if not isinstance(seconds, (int, float)):
        return 0
    return max(0, int(seconds))


def timer_summary(seconds, fallback):
    if not seconds:
        return fallback
    minutes, seconds = divmod(int(seconds), 60)
    hours, minutes = divmod(minutes, 60)
    pieces = []
    if hours:
        pieces.append(f"{hours} hr")
    if minutes:
        pieces.append(f"{minutes} min")
    if seconds or not pieces:
        pieces.append(f"{seconds} sec")
    return " · ".join(pieces)


def wake_display():
    def wake():
        try:
            subprocess.run(
                [
                    "busctl",
                    "--user",
                    "call",
                    "org.freedesktop.ScreenSaver",
                    "/ScreenSaver",
                    "org.freedesktop.ScreenSaver",
                    "SimulateUserActivity",
                ],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=4,
            )
        except (OSError, subprocess.SubprocessError):
            pass

    thread = threading.Thread(target=wake, name="display-wake", daemon=True)
    thread.start()


def reconnect_voice(reason="manual request", force=False):
    global LAST_RECONNECT

    with RECONNECT_LOCK:
        now = time.monotonic()
        if not force and now - LAST_RECONNECT < RECONNECT_COOLDOWN:
            return False
        LAST_RECONNECT = now

    HUB.note_recovery(reason)
    try:
        result = subprocess.run(
            [
                "/run/wrappers/bin/sudo",
                "-n",
                "/run/current-system/sw/bin/deck-voice-recover",
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=12,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def persist_home(home):
    if HOME_STATE_FILE is None:
        return
    try:
        HOME_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        temporary = HOME_STATE_FILE.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(home, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        temporary.chmod(0o600)
        os.replace(temporary, HOME_STATE_FILE)
    except OSError:
        pass


def runtime_audio_health():
    environment = os.environ.copy()
    environment["PIPEWIRE_RUNTIME_DIR"] = "/run/pipewire"
    while True:
        try:
            result = subprocess.run(
                ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
                check=True,
                capture_output=True,
                text=True,
                env=environment,
                timeout=4,
            )
            fields = result.stdout.strip().split()
            volume = round(float(fields[1]) * 100) if len(fields) > 1 else None
            HUB.set_health(
                pipewire=True,
                output_volume=volume,
                output_muted="[MUTED]" in result.stdout,
            )
        except (OSError, ValueError, subprocess.SubprocessError):
            HUB.set_health(pipewire=False, output_volume=None)
        time.sleep(5)


def control_tv_audio(action, value=None):
    if action == "volume-up":
        arguments = ["set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "10%+"]
    elif action == "volume-down":
        arguments = ["set-volume", "@DEFAULT_AUDIO_SINK@", "10%-"]
    elif action == "volume-mute":
        arguments = ["set-mute", "@DEFAULT_AUDIO_SINK@", "1"]
    elif action == "volume-unmute":
        arguments = ["set-mute", "@DEFAULT_AUDIO_SINK@", "0"]
    elif action == "volume-set":
        try:
            percent = float(value)
        except (TypeError, ValueError) as error:
            raise ValueError("volume value must be a number") from error
        if not 0 <= percent <= 100:
            raise ValueError("volume value must be between 0 and 100")
        arguments = [
            "set-volume",
            "-l",
            "1.0",
            "@DEFAULT_AUDIO_SINK@",
            f"{percent:g}%",
        ]
    else:
        raise ValueError("unknown audio action")

    environment = os.environ.copy()
    environment["PIPEWIRE_RUNTIME_DIR"] = "/run/pipewire"
    subprocess.run(
        ["wpctl", *arguments],
        check=True,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
    )


def close_kiosk():
    time.sleep(0.15)
    try:
        subprocess.run(
            ["systemctl", "--user", "stop", "deck-voice-visual-kiosk.service"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def restart_kiosk():
    time.sleep(0.15)
    try:
        subprocess.run(
            ["systemctl", "--user", "restart", "deck-voice-visual-kiosk.service"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
        )
    except (OSError, subprocess.SubprocessError):
        pass


HUB = StateHub()


def lva_peripheral_events():
    """Follow the local LVA WebSocket and reconnect without user action."""

    while True:
        connection = None
        try:
            connection = websocket.create_connection(
                LVA_PERIPHERAL_URL,
                timeout=6,
                enable_multithread=True,
            )
            connection.settimeout(None)
            HUB.set_voice(
                status="starting",
                label="Connecting",
                streaming=True,
                detail="Synchronizing with the voice assistant…",
            )
            while True:
                raw = connection.recv()
                if not raw:
                    raise websocket.WebSocketConnectionClosedException(
                        "peripheral connection closed"
                    )
                try:
                    message = json.loads(raw)
                except (TypeError, json.JSONDecodeError):
                    continue
                if not isinstance(message, dict):
                    continue
                name = str(message.get("event") or "")
                if not name:
                    continue
                data = message.get("data")
                HUB.lva_event(name, data if isinstance(data, dict) else {})
        except (OSError, ValueError, websocket.WebSocketException):
            HUB.set_voice(
                status="offline",
                label="Voice service offline",
                connected=False,
                streaming=False,
                detail="Waiting for the local voice service…",
            )
        finally:
            if connection is not None:
                try:
                    connection.close()
                except websocket.WebSocketException:
                    pass
        time.sleep(2)


def microphone_levels():
    command = [
        "arecord",
        "-q",
        "-D",
        "default",
        "-r",
        "16000",
        "-c",
        "1",
        "-f",
        "S16_LE",
        "-t",
        "raw",
    ]
    smoothed = 0.0
    while True:
        process = None
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            HUB.set_health(capture=True)
            while process.stdout:
                chunk = process.stdout.read(2048)
                if len(chunk) < 2:
                    break
                if len(chunk) % 2:
                    chunk = chunk[:-1]
                samples = array.array("h")
                samples.frombytes(chunk)
                rms = math.sqrt(
                    sum(sample * sample for sample in samples) / max(1, len(samples))
                )
                target = min(1.0, max(0.0, (rms - 90.0) / 3600.0)) ** 0.62
                blend = 0.48 if target > smoothed else 0.18
                smoothed += (target - smoothed) * blend
                HUB.set_audio_level(round(smoothed, 3))
        except (OSError, ValueError):
            pass
        finally:
            HUB.set_audio_level(0, capture=False)
            if process and process.poll() is None:
                process.terminate()
        time.sleep(2)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        return

    def send_bytes(self, body, content_type, status=HTTPStatus.OK):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'self' 'unsafe-inline'; "
            "script-src 'self' 'unsafe-inline'; connect-src 'self'",
        )
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def deny(self):
        self.send_bytes(b"Forbidden\n", "text/plain", HTTPStatus.FORBIDDEN)

    def read_json(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ValueError("invalid content length") from error
        if length <= 0 or length > MAX_BODY:
            raise ValueError("invalid request size")
        request = json.loads(self.rfile.read(length))
        if not isinstance(request, dict):
            raise ValueError("JSON object required")
        return request

    def do_GET(self):
        peer = self.client_address[0]
        local = is_loopback(peer)
        if self.path == "/api/health":
            if peer not in HEALTH_CLIENTS and not local:
                self.deny()
                return
            snapshot = HUB.health_snapshot()
            body = json.dumps(snapshot, ensure_ascii=False).encode(
                "utf-8"
            )
            status = (
                HTTPStatus.OK
                if snapshot["status"] == "healthy"
                else HTTPStatus.SERVICE_UNAVAILABLE
            )
            self.send_bytes(body, "application/json; charset=utf-8", status)
            return
        if not local:
            self.deny()
            return
        if self.path == "/":
            self.send_bytes(PAGE.encode("utf-8"), "text/html; charset=utf-8")
            return
        if self.path == "/api/state":
            body = json.dumps(HUB.snapshot(), ensure_ascii=False).encode("utf-8")
            self.send_bytes(body, "application/json; charset=utf-8")
            return
        if self.path == "/events":
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            client = HUB.subscribe()
            try:
                while True:
                    try:
                        event, payload = client.get(timeout=15)
                        data = json.dumps(payload, ensure_ascii=False)
                        message = f"event: {event}\ndata: {data}\n\n"
                    except queue.Empty:
                        message = ": keepalive\n\n"
                    self.wfile.write(message.encode("utf-8"))
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                HUB.unsubscribe(client)
            return
        self.send_bytes(b"Not found\n", "text/plain", HTTPStatus.NOT_FOUND)

    def do_POST(self):
        peer = self.client_address[0]
        local = is_loopback(peer)
        if self.path in {"/api/home", "/api/assistant"}:
            if peer != HOME_ASSISTANT_HOST and not local:
                self.deny()
                return
        elif self.path == "/api/event":
            if not local:
                self.deny()
                return
        elif self.path == "/api/action":
            if peer != HOME_ASSISTANT_HOST and not local:
                self.deny()
                return
        else:
            self.send_bytes(b"Not found\n", "text/plain", HTTPStatus.NOT_FOUND)
            return

        try:
            request = self.read_json()
            if self.path == "/api/home":
                HUB.set_home(sanitize(request))
            elif self.path == "/api/assistant":
                HUB.set_assistant(sanitize(request))
            elif self.path == "/api/event":
                name = str(request.get("event", ""))
                payload = request.get("payload", "")
                if not isinstance(payload, str):
                    payload = json.dumps(payload, ensure_ascii=False)
                if not name:
                    raise ValueError("event is required")
                HUB.event(name, payload)
            else:
                action = str(request.get("action", ""))
                if action == "wake":
                    wake_display()
                elif action == "reconnect":
                    HUB.set_voice(
                        status="starting",
                        label="Reconnecting",
                        detail="Refreshing the voice stream…",
                    )
                    threading.Thread(
                        target=reconnect_voice,
                        kwargs={"reason": "manual request", "force": True},
                        name="voice-reconnect",
                        daemon=True,
                    ).start()
                elif action == "display-restart":
                    threading.Thread(
                        target=restart_kiosk,
                        name="kiosk-restart",
                        daemon=True,
                    ).start()
                elif action == "close":
                    threading.Thread(
                        target=close_kiosk,
                        name="kiosk-close",
                        daemon=True,
                    ).start()
                elif action in {
                    "volume-up",
                    "volume-down",
                    "volume-mute",
                    "volume-unmute",
                    "volume-set",
                }:
                    control_tv_audio(action, request.get("value"))
                else:
                    raise ValueError("unknown action")
        except (
            ValueError,
            TypeError,
            json.JSONDecodeError,
            OSError,
            subprocess.SubprocessError,
        ) as error:
            self.send_bytes(
                str(error).encode("utf-8"),
                "text/plain; charset=utf-8",
                HTTPStatus.BAD_REQUEST,
            )
            return
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Content-Length", "0")
        self.end_headers()


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 32


def serve(page):
    global HOME_STATE_FILE, PAGE
    PAGE = page.read_text(encoding="utf-8")
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    HOME_STATE_FILE = state_home / "deck-voice-visual" / "home.json"
    try:
        saved_home = json.loads(HOME_STATE_FILE.read_text(encoding="utf-8"))
        if isinstance(saved_home, dict):
            HUB.set_home(sanitize(saved_home), persist=False)
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    threading.Thread(
        target=microphone_levels,
        name="microphone-levels",
        daemon=True,
    ).start()
    threading.Thread(
        target=runtime_audio_health,
        name="runtime-audio-health",
        daemon=True,
    ).start()
    threading.Thread(
        target=lva_peripheral_events,
        name="lva-peripheral-events",
        daemon=True,
    ).start()
    server = Server((BIND_HOST, PORT), Handler)
    print(f"Deck Voice visual listening on port {PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


def send_event(name):
    payload = sys.stdin.buffer.read(MAX_BODY).decode("utf-8", errors="replace")
    body = json.dumps(
        {"event": name, "payload": payload}, ensure_ascii=False
    ).encode("utf-8")
    request = urllib.request.Request(
        EVENT_URL,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=0.8):
            pass
    except (OSError, urllib.error.URLError):
        # The visual is optional; never interrupt the voice pipeline.
        pass


def display_geometry():
    try:
        result = subprocess.run(
            ["kscreen-doctor", "-j"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        start = result.stdout.find("{")
        config = json.loads(result.stdout[start:])
        outputs = [
            output
            for output in config.get("outputs", [])
            if output.get("connected") and output.get("enabled")
        ]
        external = [
            output
            for output in outputs
            if not output.get("name", "").startswith("eDP")
        ]
        candidates = external or outputs
        output = max(
            candidates,
            key=lambda item: item.get("size", {}).get("width", 0)
            * item.get("size", {}).get("height", 0),
        )
        position = output.get("pos", {})
        size = output.get("size", {})
        return (
            int(position.get("x", 0)),
            int(position.get("y", 0)),
            int(size.get("width", 1920)),
            int(size.get("height", 1080)),
        )
    except (OSError, subprocess.SubprocessError, ValueError, json.JSONDecodeError):
        return 0, 0, 1920, 1080


def launch():
    for _attempt in range(80):
        try:
            with urllib.request.urlopen(
                f"http://{LOOPBACK_HOST}:{PORT}/api/state", timeout=0.25
            ):
                break
        except (OSError, urllib.error.URLError):
            time.sleep(0.25)

    wake_display()
    x, y, width, height = display_geometry()
    state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    profile = state_home / "deck-voice-visual" / "chromium"
    profile.mkdir(parents=True, exist_ok=True)
    arguments = [
        "chromium",
        f"--user-data-dir={profile}",
        f"--app=http://{LOOPBACK_HOST}:{PORT}/",
        "--kiosk",
        "--no-first-run",
        "--no-default-browser-check",
        "--noerrdialogs",
        "--disable-session-crashed-bubble",
        "--disable-translate",
        "--disable-background-networking",
        "--disable-component-update",
        "--disable-background-timer-throttling",
        "--disable-backgrounding-occluded-windows",
        "--disable-renderer-backgrounding",
        "--disable-features=MediaRouter,OptimizationHints,OptimizationGuideModelDownloading,OnDeviceModel",
        "--password-store=basic",
        "--overscroll-history-navigation=0",
        "--ozone-platform=x11",
        "--force-device-scale-factor=1",
        f"--window-position={x},{y}",
        f"--window-size={width},{height}",
        "--class=DeckVoiceVisual",
    ]
    os.execvp("chromium", arguments)


def main():
    parser = argparse.ArgumentParser(description="Deck Voice visual assistant")
    parser.add_argument("--page", type=Path, required=True)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("serve")
    event_parser = subparsers.add_parser("event")
    event_parser.add_argument("name")
    subparsers.add_parser("launch")
    args = parser.parse_args()

    if args.command == "serve":
        serve(args.page)
    elif args.command == "event":
        send_event(args.name)
    elif args.command == "launch":
        launch()


if __name__ == "__main__":
    main()
