#!/usr/bin/env python3
"""Turn critical Grafana security notifications into enriched TheHive alerts."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import hmac
import ipaddress
import json
import logging
import os
import re
import ssl
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


MAX_BODY_BYTES = 1024 * 1024
MAX_OBSERVABLES = 32
MAX_ENRICHMENTS = 8
MAX_HMAC_AGE_SECONDS = 300

URL_RE = re.compile(r"https?://[^\s<>{}\[\]\"']+", re.IGNORECASE)
IPV4_RE = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
HASH_RE = re.compile(
    r"(?<![0-9a-f])(?:[0-9a-f]{64}|[0-9a-f]{40}|[0-9a-f]{32})(?![0-9a-f])",
    re.IGNORECASE,
)
DOMAIN_RE = re.compile(
    r"(?<![a-z0-9_-])(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"[a-z]{2,63}(?![a-z0-9_-])",
    re.IGNORECASE,
)
IGNORED_DOMAIN_SUFFIXES = (
    ".service",
    ".socket",
    ".target",
    ".timer",
    ".scope",
    ".slice",
    ".path",
)


class DeliveryError(RuntimeError):
    """A retryable alert-delivery failure."""


@dataclasses.dataclass(frozen=True, order=True)
class Observable:
    data_type: str
    data: str


@dataclasses.dataclass(frozen=True)
class Settings:
    listen_host: str
    listen_port: int
    state_file: Path
    thehive_url: str
    thehive_api_key_file: Path
    opencti_url: str
    opencti_api_token_file: Path
    hmac_secret_file: Path
    ca_file: Path

    @classmethod
    def from_environment(cls) -> "Settings":
        credential_directory = Path(require_environment("CREDENTIALS_DIRECTORY"))
        settings = cls(
            listen_host=os.environ.get("SECURITY_RELAY_LISTEN_HOST", "127.0.0.1"),
            listen_port=int(os.environ.get("SECURITY_RELAY_LISTEN_PORT", "9088")),
            state_file=Path(
                os.environ.get(
                    "SECURITY_RELAY_STATE_FILE",
                    "/var/lib/thorn-security-relay/state.json",
                )
            ),
            thehive_url=require_environment("SECURITY_RELAY_THEHIVE_URL").rstrip("/"),
            thehive_api_key_file=credential_directory / "thehive-api-key",
            opencti_url=require_environment("SECURITY_RELAY_OPENCTI_URL").rstrip("/"),
            opencti_api_token_file=credential_directory / "opencti-api-token",
            hmac_secret_file=credential_directory / "grafana-webhook-hmac",
            ca_file=Path(require_environment("SECURITY_RELAY_CA_FILE")),
        )
        for endpoint in (settings.thehive_url, settings.opencti_url):
            parsed = urllib.parse.urlparse(endpoint)
            if parsed.scheme != "https" or not parsed.hostname:
                raise ValueError(
                    f"integration endpoint must be an HTTPS URL: {endpoint!r}"
                )
        for secret_file in (
            settings.thehive_api_key_file,
            settings.opencti_api_token_file,
            settings.hmac_secret_file,
        ):
            if not read_secret(secret_file):
                raise ValueError(f"credential is empty: {secret_file.name}")
        return settings


def require_environment(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"missing required environment variable: {name}")
    return value


def read_secret(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def valid_hmac(
    body: bytes,
    secret: bytes,
    signature: str,
    timestamp: str,
    *,
    now: float | None = None,
) -> bool:
    if not re.fullmatch(r"[0-9a-fA-F]{64}", signature):
        return False
    try:
        timestamp_value = int(timestamp)
    except ValueError:
        return False
    current_time = time.time() if now is None else now
    if abs(current_time - timestamp_value) > MAX_HMAC_AGE_SECONDS:
        return False
    signed_body = timestamp.encode("ascii") + b":" + body
    expected = hmac.new(secret, signed_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature.lower())


def text_values(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        values: list[str] = []
        for nested in value.values():
            values.extend(text_values(nested))
        return values
    if isinstance(value, list):
        values = []
        for nested in value:
            values.extend(text_values(nested))
        return values
    return []


def extract_observables(alert: dict[str, Any]) -> list[Observable]:
    """Extract bounded, validated observables from Grafana labels/annotations."""
    strings = text_values(alert.get("labels", {})) + text_values(
        alert.get("annotations", {})
    )
    blob = "\n".join(strings)
    observables: set[Observable] = set()

    for raw_url in URL_RE.findall(blob):
        url = raw_url.rstrip(".,;:!?)")
        parsed = urllib.parse.urlparse(url)
        if parsed.hostname:
            observables.add(Observable("url", url[:4096]))
            observables.add(Observable("domain", parsed.hostname.lower().rstrip(".")))

    for raw_hash in HASH_RE.findall(blob):
        observables.add(Observable("hash", raw_hash.lower()))

    for candidate in IPV4_RE.findall(blob):
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        observables.add(Observable("ip", address.compressed))

    for candidate in DOMAIN_RE.findall(blob):
        domain = candidate.lower().rstrip(".")
        if domain.endswith(IGNORED_DOMAIN_SUFFIXES):
            continue
        try:
            ipaddress.ip_address(domain)
        except ValueError:
            observables.add(Observable("domain", domain))

    return sorted(observables)[:MAX_OBSERVABLES]


def is_enrichment_candidate(observable: Observable) -> bool:
    if observable.data_type == "ip":
        address = ipaddress.ip_address(observable.data)
        return address.is_global
    if observable.data_type == "domain":
        return not observable.data.endswith((".arpa", ".local", ".internal"))
    return observable.data_type in {"url", "hash"}


def source_reference(alert: dict[str, Any]) -> str:
    fingerprint = str(alert.get("fingerprint", "")).strip()
    if re.fullmatch(r"[A-Za-z0-9:_-]{1,112}", fingerprint):
        return f"grafana:{fingerprint}"
    canonical = json.dumps(
        {
            "labels": alert.get("labels", {}),
            "startsAt": alert.get("startsAt", ""),
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    return "grafana:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def should_route(alert: dict[str, Any]) -> bool:
    labels = alert.get("labels", {})
    if not isinstance(labels, dict):
        return False
    return (
        str(alert.get("status", "firing")).lower() == "firing"
        and str(labels.get("category", "")).lower() == "security"
        and str(labels.get("severity", "")).lower() == "critical"
    )


def parse_timestamp(value: Any) -> int:
    if not isinstance(value, str) or not value:
        return int(time.time() * 1000)
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return int(time.time() * 1000)
    return int(parsed.timestamp() * 1000)


def safe_tag(prefix: str, value: Any) -> str | None:
    normalized = re.sub(r"[^A-Za-z0-9_.:/-]+", "-", str(value).strip()).strip("-")
    if not normalized:
        return None
    return f"{prefix}:{normalized}"[:128]


def markdown_table(mapping: dict[str, Any]) -> str:
    rows = []
    for key, value in sorted(mapping.items()):
        rendered = str(value).replace("|", "\\|").replace("\n", " ")[:1024]
        rows.append(f"| `{key}` | {rendered} |")
    if not rows:
        return "_None_"
    return "| Field | Value |\n|---|---|\n" + "\n".join(rows)


def enrichment_markdown(enrichments: list[dict[str, Any]], error: str | None) -> str:
    if not enrichments:
        if error:
            return f"OpenCTI lookup was unavailable: `{error[:300]}`"
        return "No matching OpenCTI observables were found."

    sections = []
    for item in enrichments:
        labels = ", ".join(item.get("labels", [])) or "none"
        creators = ", ".join(item.get("creators", [])) or "unknown"
        references = ", ".join(item.get("references", [])) or "none"
        description = str(item.get("description", "")).replace("\n", " ")[:500]
        sections.append(
            "\n".join(
                [
                    f"- **`{item['value']}`** — `{item.get('entity_type', 'unknown')}`; "
                    f"score `{item.get('score', 'unset')}`; source {creators}",
                    f"  - labels: {labels}",
                    f"  - references: {references}",
                    *([f"  - context: {description}"] if description else []),
                ]
            )
        )
    return "\n".join(sections)


def build_thehive_payload(
    alert: dict[str, Any],
    observables: list[Observable],
    enrichments: list[dict[str, Any]],
    enrichment_error: str | None,
) -> dict[str, Any]:
    labels = alert.get("labels", {}) if isinstance(alert.get("labels"), dict) else {}
    annotations = (
        alert.get("annotations", {})
        if isinstance(alert.get("annotations"), dict)
        else {}
    )
    title = str(
        labels.get("alertname")
        or annotations.get("summary")
        or "Grafana security alert"
    )
    title = title[:512]
    description = "\n\n".join(
        [
            str(annotations.get("summary", "Critical ThornixOS security detection."))[
                :4096
            ],
            "## Grafana labels\n\n" + markdown_table(labels),
            "## Alert annotations\n\n" + markdown_table(annotations),
            "## OpenCTI enrichment\n\n"
            + enrichment_markdown(enrichments, enrichment_error),
        ]
    )

    tags = ["thornix", "grafana", "security", "severity:critical"]
    for prefix, key in (
        ("alert", "alertname"),
        ("host", "host"),
        ("rule", "grafana_folder"),
    ):
        tag = safe_tag(prefix, labels.get(key, ""))
        if tag:
            tags.append(tag)

    payload: dict[str, Any] = {
        "type": "thornix-siem",
        "source": "grafana",
        "sourceRef": source_reference(alert),
        "title": title,
        "description": description[:1048576],
        "severity": 4,
        "date": parse_timestamp(alert.get("startsAt")),
        "tags": sorted(set(tags)),
        "tlp": 2,
        "pap": 2,
        "observables": [
            {
                "dataType": observable.data_type,
                "data": observable.data,
                "message": "Extracted from the originating Grafana security alert",
            }
            for observable in observables
        ],
    }
    generator_url = str(alert.get("generatorURL", ""))
    if urllib.parse.urlparse(generator_url).scheme in {"http", "https"}:
        payload["externalLink"] = generator_url[:4096]
    return payload


class JsonClient:
    def __init__(self, token_file: Path, ca_file: Path, timeout: int = 10):
        self.token_file = token_file
        self.context = ssl.create_default_context(cafile=str(ca_file))
        self.timeout = timeout

    def post(self, url: str, payload: dict[str, Any]) -> tuple[int, dict[str, Any]]:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {read_secret(self.token_file)}",
                "Content-Type": "application/json",
                "User-Agent": "ThornixOS-security-relay/1",
            },
        )
        try:
            with urllib.request.urlopen(
                request,
                context=self.context,
                timeout=self.timeout,
            ) as response:
                response_body = response.read(MAX_BODY_BYTES)
                parsed = json.loads(response_body) if response_body else {}
                return response.status, parsed
        except urllib.error.HTTPError as error:
            response_body = error.read(MAX_BODY_BYTES)
            try:
                parsed = json.loads(response_body) if response_body else {}
            except json.JSONDecodeError:
                parsed = {"message": response_body.decode("utf-8", errors="replace")}
            setattr(error, "parsed_body", parsed)
            raise


class OpenCtiClient:
    def __init__(self, base_url: str, token_file: Path, ca_file: Path):
        self.endpoint = base_url + "/graphql"
        self.client = JsonClient(token_file, ca_file, timeout=8)

    def enrich(self, observable: Observable) -> list[dict[str, Any]]:
        value = json.dumps(observable.data)
        query = f"""
          query ThornixObservableEnrichment {{
            stixCyberObservables(
              first: 3
              filters: {{
                mode: and
                filters: [{{key: "value", values: [{value}]}}]
                filterGroups: []
              }}
            ) {{
              edges {{
                node {{
                  id
                  observable_value
                  entity_type
                  x_opencti_score
                  x_opencti_description
                  createdBy {{ name }}
                  objectLabel {{ value }}
                  externalReferences {{
                    edges {{ node {{ source_name external_id url }} }}
                  }}
                }}
              }}
            }}
          }}
        """
        _, response = self.client.post(self.endpoint, {"query": query})
        if response.get("errors"):
            raise DeliveryError(
                str(response["errors"][0].get("message", "GraphQL error"))
            )
        edges = (
            response.get("data", {}).get("stixCyberObservables", {}).get("edges", [])
        )
        results = []
        for edge in edges:
            node = edge.get("node", {})
            references = []
            for reference_edge in node.get("externalReferences", {}).get("edges", []):
                reference = reference_edge.get("node", {})
                rendered = (
                    reference.get("url")
                    or reference.get("external_id")
                    or reference.get("source_name")
                )
                if rendered:
                    references.append(str(rendered)[:300])
            results.append(
                {
                    "value": node.get("observable_value", observable.data),
                    "entity_type": node.get("entity_type", "unknown"),
                    "score": node.get("x_opencti_score"),
                    "description": node.get("x_opencti_description") or "",
                    "creators": [node["createdBy"]["name"]]
                    if node.get("createdBy", {}).get("name")
                    else [],
                    "labels": [
                        label["value"]
                        for label in node.get("objectLabel", [])
                        if label.get("value")
                    ],
                    "references": references,
                }
            )
        return results


class TheHiveClient:
    def __init__(self, base_url: str, token_file: Path, ca_file: Path):
        self.endpoint = base_url + "/api/v1/alert"
        self.client = JsonClient(token_file, ca_file, timeout=15)

    def create_alert(self, payload: dict[str, Any]) -> tuple[str, str]:
        try:
            _, response = self.client.post(self.endpoint, payload)
            return "created", str(response.get("_id", ""))
        except urllib.error.HTTPError as error:
            parsed = getattr(error, "parsed_body", {})
            message = json.dumps(parsed, sort_keys=True).lower()
            if error.code in {HTTPStatus.CONFLICT, HTTPStatus.BAD_REQUEST} and (
                "duplicate" in message
                or ("sourceref" in message and "exist" in message)
            ):
                return "duplicate", ""
            raise DeliveryError(
                f"TheHive returned HTTP {error.code}: {message[:500]}"
            ) from error
        except (OSError, ValueError) as error:
            raise DeliveryError(f"TheHive request failed: {error}") from error


class StateStore:
    def __init__(self, path: Path):
        self.path = path
        self.lock = threading.Lock()
        self.created: dict[str, dict[str, Any]] = {}
        if path.exists():
            try:
                loaded = json.loads(path.read_text(encoding="utf-8"))
                if isinstance(loaded.get("created"), dict):
                    self.created = loaded["created"]
            except (OSError, json.JSONDecodeError):
                logging.exception(
                    "could not load relay state; continuing with TheHive deduplication"
                )

    def contains(self, source_ref: str) -> bool:
        with self.lock:
            return source_ref in self.created

    def remember(self, source_ref: str, alert_id: str) -> None:
        with self.lock:
            self.created[source_ref] = {
                "alert_id": alert_id,
                "created_at": int(time.time()),
            }
            if len(self.created) > 10000:
                oldest = sorted(
                    self.created,
                    key=lambda key: int(self.created[key].get("created_at", 0)),
                )[:1000]
                for key in oldest:
                    del self.created[key]
            self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=self.path.parent,
                prefix=".state.",
                delete=False,
            ) as temporary:
                json.dump({"created": self.created}, temporary, sort_keys=True)
                temporary.write("\n")
                temporary_path = Path(temporary.name)
            temporary_path.chmod(0o600)
            os.replace(temporary_path, self.path)


class Metrics:
    NAMES = (
        "webhooks_total",
        "alerts_created_total",
        "alerts_duplicate_total",
        "alerts_filtered_total",
        "alerts_failed_total",
        "enrichment_matches_total",
        "enrichment_errors_total",
        "invalid_webhooks_total",
    )

    def __init__(self):
        self.lock = threading.Lock()
        self.values = {name: 0 for name in self.NAMES}
        self.last_success = 0.0

    def increment(self, name: str, amount: int = 1) -> None:
        with self.lock:
            self.values[name] += amount

    def success(self) -> None:
        with self.lock:
            self.last_success = time.time()

    def render(self) -> str:
        with self.lock:
            lines = []
            for name, value in self.values.items():
                lines.append(f"thorn_security_relay_{name} {value}")
            lines.append(
                f"thorn_security_relay_last_success_unixtime {self.last_success:.3f}"
            )
        return "\n".join(lines) + "\n"


class Relay:
    def __init__(self, settings: Settings):
        self.opencti = OpenCtiClient(
            settings.opencti_url,
            settings.opencti_api_token_file,
            settings.ca_file,
        )
        self.thehive = TheHiveClient(
            settings.thehive_url,
            settings.thehive_api_key_file,
            settings.ca_file,
        )
        self.state = StateStore(settings.state_file)
        self.hmac_secret = read_secret(settings.hmac_secret_file).encode("utf-8")
        self.metrics = Metrics()
        self.processing_lock = threading.Lock()

    def process_webhook(self, payload: dict[str, Any]) -> dict[str, int]:
        alerts = payload.get("alerts", [])
        if not isinstance(alerts, list):
            raise ValueError("Grafana payload has no alerts list")
        self.metrics.increment("webhooks_total")
        result = {"created": 0, "duplicate": 0, "filtered": 0}
        failures = []

        for alert in alerts:
            if not isinstance(alert, dict) or not should_route(alert):
                result["filtered"] += 1
                self.metrics.increment("alerts_filtered_total")
                continue
            try:
                outcome = self.process_alert(alert)
                result[outcome] += 1
            except Exception as error:  # The webhook must return retryable 5xx.
                logging.exception("security alert delivery failed")
                failures.append(str(error))
                self.metrics.increment("alerts_failed_total")

        if failures:
            raise DeliveryError("; ".join(failures)[:1000])
        self.metrics.success()
        return result

    def process_alert(self, alert: dict[str, Any]) -> str:
        source_ref = source_reference(alert)
        with self.processing_lock:
            if self.state.contains(source_ref):
                self.metrics.increment("alerts_duplicate_total")
                return "duplicate"

            observables = extract_observables(alert)
            enrichments: list[dict[str, Any]] = []
            enrichment_errors = []
            for observable in [
                item for item in observables if is_enrichment_candidate(item)
            ][:MAX_ENRICHMENTS]:
                try:
                    enrichments.extend(self.opencti.enrich(observable))
                except Exception as error:
                    logging.warning(
                        "OpenCTI enrichment failed for %s: %s",
                        observable.data_type,
                        error,
                    )
                    enrichment_errors.append(str(error))
                    self.metrics.increment("enrichment_errors_total")
            self.metrics.increment("enrichment_matches_total", len(enrichments))

            payload = build_thehive_payload(
                alert,
                observables,
                enrichments,
                "; ".join(enrichment_errors) if enrichment_errors else None,
            )
            outcome, alert_id = self.thehive.create_alert(payload)
            self.state.remember(source_ref, alert_id)
            self.metrics.increment(f"alerts_{outcome}_total")
            return outcome


def handler_for(relay: Relay) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "ThornSecurityRelay/1"

        def log_message(self, format_string: str, *args: Any) -> None:
            logging.info("http %s - %s", self.address_string(), format_string % args)

        def send_json(self, status: int, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            if self.path == "/health":
                self.send_json(HTTPStatus.OK, {"status": "ok"})
                return
            if self.path == "/metrics":
                body = relay.metrics.render().encode("utf-8")
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "text/plain; version=0.0.4")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})

        def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            if self.path != "/grafana":
                self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            if length <= 0 or length > MAX_BODY_BYTES:
                self.send_json(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "invalid body size"}
                )
                return
            body = self.rfile.read(length)
            if not valid_hmac(
                body,
                relay.hmac_secret,
                self.headers.get("X-Grafana-Alerting-Signature", ""),
                self.headers.get("X-Grafana-Alerting-Signature-Timestamp", ""),
            ):
                relay.metrics.increment("invalid_webhooks_total")
                self.send_json(HTTPStatus.UNAUTHORIZED, {"error": "invalid signature"})
                return
            try:
                payload = json.loads(body)
                if not isinstance(payload, dict):
                    raise ValueError("body must be a JSON object")
                result = relay.process_webhook(payload)
            except (json.JSONDecodeError, ValueError) as error:
                self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(error)[:500]})
                return
            except DeliveryError as error:
                self.send_json(HTTPStatus.BAD_GATEWAY, {"error": str(error)[:500]})
                return
            self.send_json(HTTPStatus.OK, result)

    return Handler


def serve(settings: Settings) -> None:
    relay = Relay(settings)
    server = ThreadingHTTPServer(
        (settings.listen_host, settings.listen_port),
        handler_for(relay),
    )
    logging.info(
        "security relay listening on %s:%d", settings.listen_host, settings.listen_port
    )
    server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("serve",), nargs="?", default="serve")
    args = parser.parse_args()
    logging.basicConfig(
        level=os.environ.get("SECURITY_RELAY_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    if args.command == "serve":
        serve(Settings.from_environment())


if __name__ == "__main__":
    main()
