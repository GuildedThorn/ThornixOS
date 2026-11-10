#!/usr/bin/env python3
"""Independent service probes that publish state transitions through Herald."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
from typing import Any
import urllib.error
import urllib.request


HEALTHY_STATUS_CODES = {200, 204, 301, 302, 401, 403}


def load_targets(path: Path) -> list[dict[str, str]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError("watchdog target catalog must be a list")

    targets: list[dict[str, str]] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, dict):
            raise ValueError("watchdog target must be an object")
        target = {
            "id": str(item.get("id", "")).strip(),
            "name": str(item.get("name", "")).strip(),
            "url": str(item.get("url", "")).strip(),
        }
        if not target["id"] or not target["name"]:
            raise ValueError("watchdog target is missing an id or name")
        if not target["url"].startswith(("http://", "https://")):
            raise ValueError(f"watchdog target has an unsafe URL: {target['id']}")
        if target["id"] in seen:
            raise ValueError(f"duplicate watchdog target: {target['id']}")
        seen.add(target["id"])
        targets.append(target)
    return targets


def load_state(path: Path) -> dict[str, dict[str, Any]]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (json.JSONDecodeError, OSError):
        return {}
    if not isinstance(raw, dict):
        return {}

    state: dict[str, dict[str, Any]] = {}
    for target_id, value in raw.items():
        if not isinstance(target_id, str) or not isinstance(value, dict):
            continue
        failures = value.get("failures", 0)
        if not isinstance(failures, int) or failures < 0:
            failures = 0
        state[target_id] = {
            "failures": failures,
            "notified": value.get("notified") is True,
            "detail": str(value.get("detail", ""))[:160],
        }
    return state


def save_state(path: Path, state: dict[str, dict[str, Any]]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
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
            json.dump(state, handle, sort_keys=True, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def probe_target(target: dict[str, str], timeout: float = 10.0) -> dict[str, Any]:
    request = urllib.request.Request(
        target["url"],
        headers={"User-Agent": "ThornixOS-Herald-Watchdog/1"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = int(response.status)
    except urllib.error.HTTPError as error:
        status = int(error.code)
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        reason = getattr(error, "reason", error)
        return {"healthy": False, "detail": str(reason)[:160] or "connection failed"}

    return {
        "healthy": status in HEALTHY_STATUS_CODES,
        "detail": f"HTTP {status}",
    }


def evaluate(
    targets: list[dict[str, str]],
    previous: dict[str, dict[str, Any]],
    results: dict[str, dict[str, Any]],
    failure_threshold: int = 2,
) -> tuple[dict[str, dict[str, Any]], list[dict[str, str]]]:
    if failure_threshold < 1:
        raise ValueError("failure threshold must be positive")

    state: dict[str, dict[str, Any]] = {}
    transitions: list[dict[str, str]] = []
    for target in targets:
        old = previous.get(target["id"], {})
        old_failures = old.get("failures", 0)
        if not isinstance(old_failures, int) or old_failures < 0:
            old_failures = 0
        old_notified = old.get("notified") is True
        result = results[target["id"]]
        detail = str(result.get("detail", "unknown result"))[:160]

        if result.get("healthy") is True:
            if old_notified:
                transitions.append(
                    {
                        "kind": "recovered",
                        "name": target["name"],
                        "detail": detail,
                    }
                )
            state[target["id"]] = {
                "failures": 0,
                "notified": False,
                "detail": detail,
            }
            continue

        failures = old_failures + 1
        notified = old_notified
        if failures >= failure_threshold and not notified:
            transitions.append(
                {
                    "kind": "failed",
                    "name": target["name"],
                    "detail": detail,
                }
            )
            notified = True
        state[target["id"]] = {
            "failures": failures,
            "notified": notified,
            "detail": detail,
        }
    return state, transitions


def notification(transitions: list[dict[str, str]]) -> tuple[str, str, str, str]:
    failed = [item for item in transitions if item["kind"] == "failed"]
    recovered = [item for item in transitions if item["kind"] == "recovered"]
    if failed and recovered:
        title = f"Services changed: {len(failed)} down, {len(recovered)} recovered"
    elif failed:
        title = f"{len(failed)} ThornixOS service{'s' if len(failed) != 1 else ''} unhealthy"
    else:
        title = f"{len(recovered)} ThornixOS service{'s' if len(recovered) != 1 else ''} recovered"

    lines = [
        f"DOWN · {item['name']} · {item['detail']}" for item in failed[:12]
    ] + [f"UP · {item['name']} · {item['detail']}" for item in recovered[:12]]
    omitted = len(transitions) - len(lines)
    if omitted > 0:
        lines.append(f"…and {omitted} more state changes")
    priority = "5" if failed else "3"
    tags = "rotating_light,thornixos" if failed else "heavy_check_mark,thornixos"
    return title, "\n".join(lines), priority, tags


def publish(
    ntfy_binary: str,
    topic: str,
    transitions: list[dict[str, str]],
) -> None:
    title, message, priority, tags = notification(transitions)
    result = subprocess.run(
        [
            ntfy_binary,
            "publish",
            "--quiet",
            "--title",
            title,
            "--priority",
            priority,
            "--tags",
            tags,
            "--click",
            "https://soc.guildedthorn.arpa:3000/",
            topic,
            message,
        ],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    if result.returncode != 0:
        detail = result.stderr.strip()[:300] or f"exit status {result.returncode}"
        raise RuntimeError(f"Herald notification failed: {detail}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--targets", type=Path, required=True)
    parser.add_argument("--ntfy", required=True)
    parser.add_argument(
        "--topic", default="http://127.0.0.1:2586/thornixos-ops"
    )
    parser.add_argument("--failure-threshold", type=int, default=2)
    args = parser.parse_args()

    state_directory = os.environ.get("STATE_DIRECTORY", "").strip()
    if not state_directory:
        raise RuntimeError("STATE_DIRECTORY is not set")
    state_path = Path(state_directory) / "service-state.json"
    targets = load_targets(args.targets)

    workers = min(8, max(1, len(targets)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            target["id"]: executor.submit(probe_target, target) for target in targets
        }
        results = {target_id: future.result() for target_id, future in futures.items()}

    next_state, transitions = evaluate(
        targets,
        load_state(state_path),
        results,
        failure_threshold=args.failure_threshold,
    )
    if transitions:
        publish(args.ntfy, args.topic, transitions)
    save_state(state_path, next_state)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
