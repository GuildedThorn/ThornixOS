"""Natural Kokoro TTS exposed over Wyoming with a fast Piper fallback."""

from __future__ import annotations

import argparse
import asyncio
from functools import partial
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
import math
from pathlib import Path
import re
import signal
import threading
import time
from typing import Any

import numpy as np
from sentence_stream import SentenceBoundaryDetector
import torch
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.client import AsyncTcpClient
from wyoming.error import Error
from wyoming.event import Event
from wyoming.info import Attribution, Describe, Info, TtsProgram, TtsVoice
from wyoming.server import AsyncEventHandler, AsyncServer
from wyoming.tts import (
    Synthesize,
    SynthesizeChunk,
    SynthesizeStart,
    SynthesizeStop,
    SynthesizeStopped,
)

_LOGGER = logging.getLogger("wyoming_kokoro")
SAMPLE_RATE = 24_000
SAMPLE_WIDTH = 2
CHANNELS = 1
SAMPLES_PER_CHUNK = 2_400

_FAST_ACK = re.compile(
    r"^(okay|done|turning|muting|unmuting|paused|resumed|stopped|skipping|"
    r"going back|added|checked|removed|timer|the dashboard|reconnecting|"
    r"microphone tuning|wake-word sensitivity|tv volume)",
    re.IGNORECASE,
)

_SPOKEN_REPLACEMENTS = (
    (re.compile(r"\bSOC\b"), "S O C"),
    (re.compile(r"\bSEM\b"), "S E M"),
    (re.compile(r"\bDDoS\b", re.IGNORECASE), "D D O S"),
    (re.compile(r"\bCPU\b"), "C P U"),
    (re.compile(r"\bGPU\b"), "G P U"),
    (re.compile(r"\bRAM\b"), "ram"),
    (re.compile(r"\bHDMI\b"), "H D M I"),
    (re.compile(r"\bNixOS\b", re.IGNORECASE), "Nix O S"),
    (re.compile(r"\bHome Assistant\b", re.IGNORECASE), "Home Assistant"),
)


def normalize_for_speech(text: str) -> str:
    """Turn screen-oriented text into natural spoken English."""
    spoken = text.replace("**", "").replace("`", "")
    spoken = re.sub(r"(?<=\d)\s*°\s*F(?:ahrenheit)?", " degrees Fahrenheit", spoken)
    spoken = re.sub(r"(?<=\d)\s*°\s*C(?:elsius)?", " degrees Celsius", spoken)
    spoken = re.sub(r"\s*\(\s*degrees (?:Fahrenheit|Celsius)\s*\)", "", spoken)
    spoken = re.sub(r"\s*\(\s*°[FC]\s*\)", "", spoken)
    spoken = re.sub(r"(?m)^\s*[-•]\s+", "", spoken)
    spoken = spoken.replace("_", " ")
    for pattern, replacement in _SPOKEN_REPLACEMENTS:
        spoken = pattern.sub(replacement, spoken)
    spoken = re.sub(r"\s+", " ", spoken).strip()
    return spoken


def should_use_fast_voice(text: str) -> bool:
    """Use Piper for short deterministic acknowledgements."""
    return len(text.split()) <= 16 and bool(_FAST_ACK.search(text))


class StreamingVoiceSelector:
    """Choose one engine per Wyoming stream without delaying normal replies."""

    def __init__(self) -> None:
        self.mode: str | None = None
        self._pending: list[str] = []

    def add(self, raw_text: str) -> tuple[str | None, str]:
        text = normalize_for_speech(raw_text)
        if not text:
            return None, ""
        if self.mode is not None:
            return self.mode, text

        self._pending.append(text)
        combined = " ".join(self._pending)
        if should_use_fast_voice(combined):
            return None, ""

        self.mode = "natural"
        self._pending.clear()
        return self.mode, combined

    def finish(self, raw_text: str = "") -> tuple[str | None, str]:
        mode, text = self.add(raw_text)
        if mode is not None:
            return mode, text
        if not self._pending:
            return None, ""

        text = " ".join(self._pending)
        self._pending.clear()
        self.mode = "fast" if should_use_fast_voice(text) else "natural"
        return self.mode, text


class HealthState:
    def __init__(self, voice: str) -> None:
        self._lock = threading.Lock()
        self._state: dict[str, Any] = {
            "status": "starting",
            "engine": "Kokoro 82M",
            "voice": voice,
            "sample_rate": SAMPLE_RATE,
            "started_at": time.time(),
            "synthesis_count": 0,
            "natural_count": 0,
            "fast_count": 0,
            "fallback_count": 0,
            "last_synthesis_seconds": None,
            "last_mode": None,
            "last_error": "",
        }

    def update(self, **changes: Any) -> None:
        with self._lock:
            self._state.update(changes)

    def record(self, mode: str, elapsed: float, fallback: bool = False) -> None:
        with self._lock:
            self._state["status"] = "ready"
            self._state["synthesis_count"] += 1
            self._state[f"{mode}_count"] += 1
            if fallback:
                self._state["fallback_count"] += 1
            self._state["last_synthesis_seconds"] = round(elapsed, 3)
            self._state["last_mode"] = mode
            self._state["last_error"] = ""

    def error(self, message: str) -> None:
        with self._lock:
            self._state["status"] = "degraded"
            self._state["last_error"] = message[:300]

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            state = dict(self._state)
        state["uptime_seconds"] = round(time.time() - state["started_at"], 1)
        return state


class KokoroEngine:
    def __init__(
        self,
        config_path: Path,
        model_path: Path,
        voice_path: Path,
        speed: float,
    ) -> None:
        from kokoro import KModel, KPipeline

        self._lock = threading.Lock()
        self._voice_path = str(voice_path)
        self._speed = speed
        model = KModel(
            repo_id="hexgrad/Kokoro-82M",
            config=str(config_path),
            model=str(model_path),
        ).to("cpu").eval()
        self._pipeline = KPipeline(
            lang_code="a",
            repo_id="hexgrad/Kokoro-82M",
            model=model,
        )
        # Load the selected voice during startup, not on the first spoken reply.
        self._pipeline.load_voice(self._voice_path)

    def synthesize(self, text: str) -> bytes:
        """Synthesize mono 24 kHz PCM."""
        pieces: list[np.ndarray] = []
        with self._lock, torch.inference_mode():
            for result in self._pipeline(
                text,
                voice=self._voice_path,
                speed=self._speed,
                split_pattern=r"\n+",
            ):
                if result.audio is None:
                    continue
                audio = result.audio.detach().cpu().clamp(-1.0, 1.0).numpy()
                pieces.append(audio.astype(np.float32, copy=False))
        if not pieces:
            return b""
        joined = np.concatenate(pieces)
        return (joined * 32767.0).astype(np.int16).tobytes()


class KokoroEventHandler(AsyncEventHandler):
    def __init__(
        self,
        info: Info,
        engine: KokoroEngine,
        health: HealthState,
        piper_host: str,
        piper_port: int,
        *args: Any,
        **kwargs: Any,
    ) -> None:
        super().__init__(*args, **kwargs)
        self._info_event = info.event()
        self._engine = engine
        self._health = health
        self._piper_host = piper_host
        self._piper_port = piper_port
        self._streaming = False
        self._stream_started = False
        self._detector = SentenceBoundaryDetector()
        self._stream_selector = StreamingVoiceSelector()

    async def handle_event(self, event: Event) -> bool:
        if Describe.is_type(event.type):
            await self.write_event(self._info_event)
            return True

        try:
            if SynthesizeStart.is_type(event.type):
                self._streaming = True
                self._stream_started = False
                self._detector = SentenceBoundaryDetector()
                self._stream_selector = StreamingVoiceSelector()
                return True

            if SynthesizeChunk.is_type(event.type):
                if not self._streaming:
                    return True
                chunk = SynthesizeChunk.from_event(event)
                for sentence in self._detector.add_chunk(chunk.text):
                    mode, text = self._stream_selector.add(sentence)
                    if mode is not None:
                        await self._render(
                            text,
                            send_start=not self._stream_started,
                            send_stop=False,
                            mode=mode,
                        )
                        self._stream_started = True
                return True

            if Synthesize.is_type(event.type):
                if self._streaming:
                    # Home Assistant sends the full text for compatibility after
                    # already sending streaming chunks.
                    return True
                request = Synthesize.from_event(event)
                await self._render_non_streaming(request.text)
                return True

            if SynthesizeStop.is_type(event.type):
                if not self._streaming:
                    return True
                final_text = self._detector.finish()
                mode, text = self._stream_selector.finish(final_text)
                if mode is not None:
                    await self._render(
                        text,
                        send_start=not self._stream_started,
                        send_stop=False,
                        mode=mode,
                    )
                    self._stream_started = True
                await self.write_event(SynthesizeStopped().event())
                self._streaming = False
                return True

            return True
        except Exception as err:  # noqa: BLE001 - report protocol errors to HA
            _LOGGER.exception("TTS request failed")
            self._health.error(str(err))
            await self.write_event(
                Error(text=str(err), code=err.__class__.__name__).event()
            )
            return True

    async def _render_non_streaming(self, raw_text: str) -> None:
        if not normalize_for_speech(raw_text):
            await self.write_event(AudioStop().event())
            return
        # Choose one engine for the entire non-streaming request. Switching
        # between Piper and Kokoro at sentence boundaries changes sample rate
        # inside one Wyoming stream and produces corrupt playback downstream.
        await self._render(raw_text, send_start=True, send_stop=True)

    async def _render(
        self,
        raw_text: str,
        send_start: bool,
        send_stop: bool,
        mode: str | None = None,
    ) -> None:
        text = normalize_for_speech(raw_text)
        if not text:
            if send_stop:
                await self.write_event(AudioStop().event())
            return

        started = time.monotonic()
        if mode == "fast" or (mode is None and should_use_fast_voice(text)):
            try:
                async with asyncio.timeout(3.0):
                    await self._render_with_piper(text, send_start, send_stop)
                self._health.record("fast", time.monotonic() - started)
                return
            except (OSError, ConnectionError, TimeoutError) as err:
                _LOGGER.warning("Piper fallback unavailable: %s", err)
                self._health.error(str(err))
                fallback = True
        else:
            fallback = False

        audio = await asyncio.to_thread(self._engine.synthesize, text)
        await self._write_pcm(audio, send_start, send_stop)
        self._health.record(
            "natural",
            time.monotonic() - started,
            fallback=fallback,
        )

    async def _render_with_piper(
        self, text: str, send_start: bool, send_stop: bool
    ) -> None:
        async with AsyncTcpClient(self._piper_host, self._piper_port) as client:
            await client.write_event(Synthesize(text=text).event())
            upstream_started = False
            while event := await client.read_event():
                if AudioStart.is_type(event.type):
                    if send_start and not upstream_started:
                        await self.write_event(event)
                    upstream_started = True
                elif AudioChunk.is_type(event.type):
                    await self.write_event(event)
                elif AudioStop.is_type(event.type):
                    if send_stop:
                        await self.write_event(AudioStop().event())
                    return
            raise ConnectionError("Piper closed the connection before audio completed")

    async def _write_pcm(
        self, audio: bytes, send_start: bool, send_stop: bool
    ) -> None:
        if send_start:
            await self.write_event(
                AudioStart(
                    rate=SAMPLE_RATE,
                    width=SAMPLE_WIDTH,
                    channels=CHANNELS,
                ).event()
            )
        bytes_per_chunk = SAMPLES_PER_CHUNK * SAMPLE_WIDTH * CHANNELS
        chunks = math.ceil(len(audio) / bytes_per_chunk)
        for index in range(chunks):
            offset = index * bytes_per_chunk
            await self.write_event(
                AudioChunk(
                    audio=audio[offset : offset + bytes_per_chunk],
                    rate=SAMPLE_RATE,
                    width=SAMPLE_WIDTH,
                    channels=CHANNELS,
                ).event()
            )
        if send_stop:
            await self.write_event(AudioStop().event())


def start_health_server(host: str, port: int, health: HealthState) -> None:
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, _format: str, *_args: Any) -> None:
            return

        def do_GET(self) -> None:
            if self.path != "/health":
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            snapshot = health.snapshot()
            body = json.dumps(snapshot, separators=(",", ":")).encode()
            self.send_response(
                HTTPStatus.OK
                if snapshot["status"] == "ready"
                else HTTPStatus.SERVICE_UNAVAILABLE
            )
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer((host, port), Handler)
    thread = threading.Thread(
        target=server.serve_forever,
        name="kokoro-health",
        daemon=True,
    )
    thread.start()


async def async_main() -> None:
    parser = argparse.ArgumentParser(description="Casita Wyoming Kokoro TTS")
    parser.add_argument("--uri", default="tcp://0.0.0.0:10201")
    parser.add_argument("--health-host", default="0.0.0.0")
    parser.add_argument("--health-port", type=int, default=10202)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--voice", type=Path, required=True)
    parser.add_argument("--voice-name", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.04)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--piper-host", default="172.16.25.2")
    parser.add_argument("--piper-port", type=int, default=10200)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    torch.set_num_threads(max(1, args.threads))
    torch.set_num_interop_threads(1)

    health = HealthState(args.voice_name)
    _LOGGER.info("Loading Kokoro model and %s voice", args.voice_name)
    engine = await asyncio.to_thread(
        KokoroEngine,
        args.config,
        args.model,
        args.voice,
        args.speed,
    )
    health.update(status="ready")
    start_health_server(args.health_host, args.health_port, health)

    info = Info(
        tts=[
            TtsProgram(
                name="kokoro",
                description="Casita natural local voice with fast Piper fallback",
                attribution=Attribution(
                    name="hexgrad",
                    url="https://huggingface.co/hexgrad/Kokoro-82M",
                ),
                installed=True,
                voices=[
                    TtsVoice(
                        name=args.voice_name,
                        description="Casita Heart · natural",
                        attribution=Attribution(
                            name="hexgrad",
                            url="https://huggingface.co/hexgrad/Kokoro-82M",
                        ),
                        installed=True,
                        version="1.0",
                        languages=["en_US"],
                    )
                ],
                version="1.0.0",
                supports_synthesize_streaming=True,
            )
        ]
    )

    server = AsyncServer.from_uri(args.uri)
    server_task = asyncio.create_task(
        server.run(
            partial(
                KokoroEventHandler,
                info,
                engine,
                health,
                args.piper_host,
                args.piper_port,
            )
        )
    )
    loop = asyncio.get_running_loop()
    loop.add_signal_handler(signal.SIGINT, server_task.cancel)
    loop.add_signal_handler(signal.SIGTERM, server_task.cancel)
    _LOGGER.info("Kokoro Wyoming server ready at %s", args.uri)
    try:
        await server_task
    except asyncio.CancelledError:
        _LOGGER.info("Kokoro Wyoming server stopped")


def main() -> None:
    asyncio.run(async_main())


if __name__ == "__main__":
    main()
