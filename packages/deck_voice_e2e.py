#!/usr/bin/env python3
"""Run a real acoustic Deck Voice transaction and publish durable proof."""

from __future__ import annotations

import argparse
import array
import asyncio
import fcntl
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time
from typing import Any
import urllib.error
import urllib.request
import wave

import websocket
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.client import AsyncTcpClient
from wyoming.tts import Synthesize


STAGES = ("microphone", "wake_word", "stt", "conversation", "tts", "hdmi")


class CheckFailed(RuntimeError):
    def __init__(self, stage: str, detail: str) -> None:
        super().__init__(detail)
        self.stage = stage


class CheckSkipped(RuntimeError):
    pass


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    return value if isinstance(value, dict) else {}


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as handle:
            temporary = handle.name
            json.dump(value, handle, sort_keys=True, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def atomic_text(path: Path, value: str) -> None:
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    temporary: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as handle:
            temporary = handle.name
            handle.write(value)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if temporary:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def pcm_stats(raw: bytes) -> tuple[float, int]:
    if len(raw) % 2:
        raw = raw[:-1]
    samples = array.array("h")
    samples.frombytes(raw)
    if not samples:
        return 0.0, 0
    if os.sys.byteorder != "little":
        samples.byteswap()
    square_sum = sum(sample * sample for sample in samples)
    return math.sqrt(square_sum / len(samples)), max(abs(sample) for sample in samples)


def build_status(
    previous: dict[str, Any],
    *,
    success: bool,
    now: float,
    duration: float,
    stage: str,
    detail: str,
    completed: set[str],
    microphone_rms: float = 0.0,
    hdmi_rms: float = 0.0,
    hdmi_peak: int = 0,
    transcript: str = "",
    response: str = "",
) -> dict[str, Any]:
    last_success = now if success else float(previous.get("last_success", 0) or 0)
    return {
        "version": 1,
        "success": success,
        "last_attempt": round(now, 3),
        "last_success": round(last_success, 3),
        "duration_seconds": round(max(0.0, duration), 3),
        "stage": stage[:32],
        "detail": detail.replace("\n", " ")[:240],
        "completed_stages": [item for item in STAGES if item in completed],
        "microphone_rms": round(max(0.0, microphone_rms), 2),
        "hdmi_rms": round(max(0.0, hdmi_rms), 2),
        "hdmi_peak": max(0, int(hdmi_peak)),
        "transcript": transcript.replace("\n", " ")[:160],
        "response": response.replace("\n", " ")[:240],
    }


def render_metrics(status: dict[str, Any]) -> str:
    completed = set(status.get("completed_stages") or [])
    lines = [
        "# HELP thorn_deck_voice_e2e_success Whether the latest acoustic voice transaction succeeded.",
        "# TYPE thorn_deck_voice_e2e_success gauge",
        f"thorn_deck_voice_e2e_success {1 if status.get('success') else 0}",
        "# HELP thorn_deck_voice_e2e_last_attempt_seconds Unix time of the latest acoustic transaction.",
        "# TYPE thorn_deck_voice_e2e_last_attempt_seconds gauge",
        f"thorn_deck_voice_e2e_last_attempt_seconds {float(status.get('last_attempt', 0) or 0):.3f}",
        "# HELP thorn_deck_voice_e2e_last_success_seconds Unix time of the latest successful acoustic transaction.",
        "# TYPE thorn_deck_voice_e2e_last_success_seconds gauge",
        f"thorn_deck_voice_e2e_last_success_seconds {float(status.get('last_success', 0) or 0):.3f}",
        "# HELP thorn_deck_voice_e2e_duration_seconds Duration of the latest acoustic transaction.",
        "# TYPE thorn_deck_voice_e2e_duration_seconds gauge",
        f"thorn_deck_voice_e2e_duration_seconds {float(status.get('duration_seconds', 0) or 0):.3f}",
        "# HELP thorn_deck_voice_e2e_microphone_rms Microphone sample RMS before the transaction.",
        "# TYPE thorn_deck_voice_e2e_microphone_rms gauge",
        f"thorn_deck_voice_e2e_microphone_rms {float(status.get('microphone_rms', 0) or 0):.2f}",
        "# HELP thorn_deck_voice_e2e_hdmi_rms HDMI monitor RMS during the assistant response.",
        "# TYPE thorn_deck_voice_e2e_hdmi_rms gauge",
        f"thorn_deck_voice_e2e_hdmi_rms {float(status.get('hdmi_rms', 0) or 0):.2f}",
        "# HELP thorn_deck_voice_e2e_stage_success Whether each stage completed in the latest transaction.",
        "# TYPE thorn_deck_voice_e2e_stage_success gauge",
    ]
    lines.extend(
        f'thorn_deck_voice_e2e_stage_success{{stage="{stage}"}} {1 if stage in completed else 0}'
        for stage in STAGES
    )
    return "\n".join(lines) + "\n"


async def synthesize(host: str, port: int, text: str) -> tuple[bytes, int, int, int]:
    audio = bytearray()
    rate = width = channels = 0
    async with AsyncTcpClient(host, port) as client:
        await client.write_event(Synthesize(text=text).event())
        while event := await asyncio.wait_for(client.read_event(), timeout=30):
            if AudioStart.is_type(event.type):
                start = AudioStart.from_event(event)
                rate, width, channels = start.rate, start.width, start.channels
            elif AudioChunk.is_type(event.type):
                chunk = AudioChunk.from_event(event)
                if not rate:
                    rate, width, channels = chunk.rate, chunk.width, chunk.channels
                if (chunk.rate, chunk.width, chunk.channels) != (rate, width, channels):
                    raise CheckFailed("conversation", "TTS changed audio format mid-stream")
                audio.extend(chunk.audio)
            elif AudioStop.is_type(event.type):
                break
    if not audio or min(rate, width, channels) < 1:
        raise CheckFailed("conversation", "local TTS returned no prompt audio")
    return bytes(audio), rate, width, channels


def write_wav(path: Path, audio: bytes, rate: int, width: int, channels: int) -> None:
    with wave.open(str(path), "wb") as output:
        output.setframerate(rate)
        output.setsampwidth(width)
        output.setnchannels(channels)
        output.writeframes(audio)


def read_health(url: str) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "ThornixOS-Deck-Voice-E2E/1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            value = json.loads(response.read(65536))
    except urllib.error.HTTPError as error:
        # A previous end-to-end failure deliberately makes the public health
        # endpoint return 503. Its bounded JSON body still carries the core
        # connection/capture state needed to run a recovery transaction.
        try:
            value = json.loads(error.read(65536))
        except (json.JSONDecodeError, OSError) as body_error:
            raise CheckFailed(
                "microphone", f"voice health endpoint failed: {error}"
            ) from body_error
    except Exception as error:  # noqa: BLE001 - convert transport errors to a stage
        raise CheckFailed("microphone", f"voice health endpoint failed: {error}") from error
    if not isinstance(value, dict):
        raise CheckFailed("microphone", "voice health endpoint returned invalid JSON")
    return value


def microphone_sample(command: str) -> tuple[float, int]:
    try:
        result = subprocess.run(
            [
                command,
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
                "-d",
                "1",
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=8,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise CheckFailed("microphone", f"microphone capture failed: {error}") from error
    rms, peak = pcm_stats(result.stdout)
    if len(result.stdout) < 16000 or peak < 8:
        raise CheckFailed("microphone", "microphone produced silence or too few samples")
    return rms, peak


def recent_wake_word(command: str, unit: str, max_age: int) -> None:
    try:
        result = subprocess.run(
            [
                command,
                "--unit",
                unit,
                "--since",
                f"{max_age} seconds ago",
                "--grep",
                "wake_word_triggered.flac",
                "--lines",
                "1",
                "--no-pager",
                "--output",
                "cat",
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise CheckFailed("wake_word", f"could not inspect wake-word proof: {error}") from error
    if not result.stdout.strip():
        raise CheckFailed(
            "wake_word",
            f"no physical wake-word detection was recorded in {max_age // 3600} hours",
        )


def receive_event(connection: Any, deadline: float) -> tuple[str, dict[str, Any]]:
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("voice event deadline expired")
        connection.settimeout(min(remaining, 5.0))
        try:
            raw = connection.recv()
        except websocket.WebSocketTimeoutException:
            continue
        if not raw:
            raise ConnectionError("voice peripheral connection closed")
        try:
            value = json.loads(raw)
        except (TypeError, json.JSONDecodeError):
            continue
        if not isinstance(value, dict):
            continue
        name = str(value.get("event") or "")
        data = value.get("data")
        if name:
            return name, data if isinstance(data, dict) else {}


def wait_for(connection: Any, expected: str, timeout: float, stage: str) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    while True:
        try:
            name, data = receive_event(connection, deadline)
        except (ConnectionError, OSError, TimeoutError) as error:
            raise CheckFailed(stage, f"did not observe {expected}: {error}") from error
        if name == "pipeline_error":
            reason = str(data.get("reason") or "voice pipeline error")
            raise CheckFailed(stage, reason)
        if name == "disconnected":
            raise CheckFailed(stage, "Home Assistant disconnected during the transaction")
        if name == expected:
            return data


def play(command: str, sink: str, path: Path, volume: float) -> None:
    try:
        subprocess.run(
            [command, "--target", sink, "--volume", str(volume), str(path)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise CheckFailed("hdmi", f"HDMI prompt playback failed: {error}") from error


def start_monitor(command: str, sink: str, path: Path) -> subprocess.Popen[bytes]:
    try:
        process = subprocess.Popen(
            [
                command,
                "--target",
                sink,
                "--properties",
                "{ stream.capture.sink = true }",
                "--rate",
                "48000",
                "--channels",
                "2",
                "--format",
                "s16",
                "--raw",
                str(path),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise CheckFailed("hdmi", f"could not start HDMI monitor: {error}") from error
    time.sleep(0.2)
    if process.poll() is not None:
        detail = (process.stderr.read() if process.stderr else b"").decode(
            errors="replace"
        )[:200]
        raise CheckFailed("hdmi", f"HDMI monitor exited early: {detail}")
    return process


def stop_process(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=2)


def perform(
    args: argparse.Namespace,
    completed: set[str],
    evidence: dict[str, Any],
) -> dict[str, Any]:
    health = read_health(args.health_url)
    if health.get("voice_state") not in {"idle", "done"}:
        raise CheckSkipped(f"voice is currently {health.get('voice_state', 'busy')}")
    audio_health = health.get("audio") if isinstance(health.get("audio"), dict) else {}
    if not (
        health.get("connected") is True
        and health.get("streaming") is True
        and audio_health.get("pipewire") is True
        and audio_health.get("capture") is True
    ):
        raise CheckFailed("microphone", "voice connection or capture is not healthy")
    if audio_health.get("output_muted") is True:
        raise CheckFailed("hdmi", "HDMI output is muted")
    volume = float(audio_health.get("output_volume", 0) or 0)
    if volume < 15:
        raise CheckFailed("hdmi", "HDMI output volume is below 15 percent")

    microphone_rms, _ = microphone_sample(args.arecord)
    evidence["microphone_rms"] = microphone_rms
    completed.add("microphone")
    recent_wake_word(args.journalctl, args.voice_unit, args.wake_proof_max_age)
    completed.add("wake_word")

    with tempfile.TemporaryDirectory(prefix="deck-voice-e2e-") as temp_name:
        temp = Path(temp_name)
        command_path = temp / "command.wav"
        command_audio = asyncio.run(
            synthesize(args.tts_host, args.tts_port, args.command_text)
        )
        write_wav(command_path, *command_audio)

        connection = None
        recorder: subprocess.Popen[bytes] | None = None
        pipeline_started = False
        finished = False
        monitor_path = temp / "hdmi.raw"
        monitor_offset = 0
        transcript = ""
        response = ""
        try:
            connection = websocket.create_connection(args.peripheral_url, timeout=6)
            snapshot = wait_for(connection, "snapshot", 8, "microphone")
            if snapshot.get("ha_connected") is not True:
                raise CheckFailed("microphone", "voice satellite is disconnected from Home Assistant")
            if snapshot.get("muted") is True:
                raise CheckFailed("microphone", "voice satellite microphone is muted")

            connection.send(json.dumps({"command": "start_listening"}))
            wait_for(connection, "listening", 8, "wake_word")
            pipeline_started = True

            play(args.pw_play, args.sink, command_path, args.prompt_volume)
            recorder = start_monitor(args.pw_record, args.sink, monitor_path)

            deadline = time.monotonic() + 55
            seen_tts_speaking = False
            while not finished:
                try:
                    name, data = receive_event(connection, deadline)
                except (ConnectionError, OSError, TimeoutError) as error:
                    raise CheckFailed("tts", f"voice transaction timed out: {error}") from error
                if name == "pipeline_error":
                    reason = str(data.get("reason") or "voice pipeline error")
                    stage = "stt" if not transcript else "conversation"
                    raise CheckFailed(stage, reason)
                if name == "disconnected":
                    raise CheckFailed("conversation", "Home Assistant disconnected during the transaction")
                if name == "stt_text":
                    transcript = str(data.get("text") or "").strip()
                    evidence["transcript"] = transcript
                    if "time" not in transcript.lower():
                        raise CheckFailed("stt", f"unexpected transcript: {transcript or 'empty'}")
                    completed.add("stt")
                elif name == "tts_text":
                    response = str(data.get("text") or "").strip()
                    evidence["response"] = response
                    if not response:
                        raise CheckFailed("conversation", "conversation returned empty text")
                    completed.add("conversation")
                elif name == "tts_speaking":
                    seen_tts_speaking = True
                    try:
                        monitor_offset = monitor_path.stat().st_size
                    except FileNotFoundError:
                        monitor_offset = 0
                elif name == "tts_finished":
                    if not seen_tts_speaking:
                        raise CheckFailed("tts", "TTS finished without a speaking event")
                    completed.add("tts")
                    finished = True

            stop_process(recorder)
            recorder = None
            raw = monitor_path.read_bytes()[monitor_offset:]
            hdmi_rms, hdmi_peak = pcm_stats(raw)
            evidence["hdmi_rms"] = hdmi_rms
            evidence["hdmi_peak"] = hdmi_peak
            if len(raw) < 9600 or hdmi_rms < 60 or hdmi_peak < 300:
                raise CheckFailed(
                    "hdmi",
                    f"assistant response was silent on HDMI (rms={hdmi_rms:.1f}, peak={hdmi_peak})",
                )
            completed.add("hdmi")
            return evidence
        finally:
            stop_process(recorder)
            if connection is not None:
                if pipeline_started and not finished:
                    try:
                        connection.send(json.dumps({"command": "stop_pipeline"}))
                    except websocket.WebSocketException:
                        pass
                connection.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--status-file", type=Path, required=True)
    parser.add_argument("--metrics-file", type=Path, required=True)
    parser.add_argument("--health-url", default="http://127.0.0.1:10701/api/health")
    parser.add_argument("--peripheral-url", default="ws://127.0.0.1:6055")
    parser.add_argument("--tts-host", default="127.0.0.1")
    parser.add_argument("--tts-port", type=int, default=10201)
    parser.add_argument(
        "--sink", default="alsa_output.pci-0000_04_00.1.hdmi-stereo-extra2"
    )
    parser.add_argument("--command-text", default="What time is it?")
    parser.add_argument("--prompt-volume", type=float, default=0.78)
    parser.add_argument("--journalctl", default="journalctl")
    parser.add_argument("--voice-unit", default="linux-voice-assistant.service")
    parser.add_argument("--wake-proof-max-age", type=int, default=7 * 24 * 60 * 60)
    parser.add_argument("--arecord", default="arecord")
    parser.add_argument("--pw-play", default="pw-play")
    parser.add_argument("--pw-record", default="pw-record")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.status_file.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    lock_path = args.status_file.parent / "check.lock"
    started = time.monotonic()
    completed: set[str] = set()
    evidence: dict[str, Any] = {
        "microphone_rms": 0.0,
        "hdmi_rms": 0.0,
        "hdmi_peak": 0,
        "transcript": "",
        "response": "",
    }
    with lock_path.open("a+", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Deck Voice end-to-end check is already running", flush=True)
            return 0

        try:
            perform(args, completed, evidence)
        except CheckSkipped as error:
            print(f"Deck Voice end-to-end check skipped: {error}", flush=True)
            return 0
        except Exception as error:  # noqa: BLE001 - always persist failure evidence
            stage = error.stage if isinstance(error, CheckFailed) else "internal"
            detail = str(error) or error.__class__.__name__
            status = build_status(
                load_json(args.status_file),
                success=False,
                now=time.time(),
                duration=time.monotonic() - started,
                stage=stage,
                detail=detail,
                completed=completed,
                **evidence,
            )
            atomic_json(args.status_file, status)
            atomic_text(args.metrics_file, render_metrics(status))
            print(f"Deck Voice end-to-end check failed at {stage}: {detail}", flush=True)
            return 1

        status = build_status(
            load_json(args.status_file),
            success=True,
            now=time.time(),
            duration=time.monotonic() - started,
            stage="complete",
            detail="microphone through HDMI response verified",
            completed=completed,
            **evidence,
        )
        atomic_json(args.status_file, status)
        atomic_text(args.metrics_file, render_metrics(status))
        print(
            "Deck Voice end-to-end check passed "
            f"in {status['duration_seconds']:.1f}s "
            f"(HDMI rms={status['hdmi_rms']:.1f})",
            flush=True,
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
