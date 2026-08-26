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
MAX_NEWS_CONTEXT_BODY_BYTES = 32 * 1024
MAX_NEWS_CONTEXT_TERMS = 8
MAX_NEWS_CONTEXT_HITS = 40
MAX_NEWS_CONTEXT_RESPONSE_BYTES = 2 * 1024 * 1024
NEWS_CONTEXT_LOOKBACK = "30d"
MAX_OPS_SUMMARY_BODY_BYTES = 4 * 1024
MAX_OPS_QUERY_RESPONSE_BYTES = 2 * 1024 * 1024
MAX_OPS_VECTOR_RESULTS = 256
OPS_SUMMARY_WINDOWS = ("24h", "7d")

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
NEWS_CONTEXT_KINDS = (
    "actors",
    "campaigns",
    "malware",
    "vulnerabilities",
    "techniques",
    "indicators",
)
GENERIC_NEWS_CONTEXT_TERMS = {
    "campaign",
    "cisa",
    "cloud",
    "cybersecurity",
    "google",
    "linux",
    "malware",
    "microsoft",
    "microsoft security",
    "ransomware",
    "security",
    "threat actor",
    "windows",
}
NEWS_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._+/@:-]{2,127}$")
CVE_RE = re.compile(r"^CVE-[0-9]{4}-[0-9]{4,7}$", re.IGNORECASE)
TECHNIQUE_RE = re.compile(r"^T[0-9]{4}(?:\.[0-9]{3})?$", re.IGNORECASE)
# Never search the journal stream here: Loki, the relay, and OpenCTI write the
# queried term into their own operational logs, which would turn a lookup into
# self-generated evidence. Restrict correlation to actual sensor/syslog data.
LOKI_CONTEXT_JOBS = "suricata|zeek|syslog"
SAFE_LOKI_LABELS = (
    "app",
    "facility",
    "host",
    "job",
    "level",
    "severity",
    "unit",
)
INTERNAL_ACME_SUFFIXES = (".guildedthorn.arpa",)


class DeliveryError(RuntimeError):
    """A retryable alert-delivery failure."""


def is_internal_acme_hostname(hostname: str) -> bool:
    normalized = hostname.rstrip(".").casefold()
    return any(normalized.endswith(suffix) for suffix in INTERNAL_ACME_SUFFIXES)


@dataclasses.dataclass(frozen=True, order=True)
class Observable:
    data_type: str
    data: str


@dataclasses.dataclass(frozen=True, order=True)
class ContextTerm:
    kind: str
    value: str


@dataclasses.dataclass(frozen=True)
class Settings:
    listen_host: str
    listen_port: int
    state_file: Path
    thehive_url: str
    thehive_api_key_file: Path
    opencti_url: str
    opencti_api_token_file: Path
    loki_url: str
    prometheus_url: str
    backup_catalog_file: Path
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
            loki_url=os.environ.get(
                "SECURITY_RELAY_LOKI_URL", "http://127.0.0.1:3101"
            ).rstrip("/"),
            prometheus_url=os.environ.get(
                "SECURITY_RELAY_PROMETHEUS_URL", "http://127.0.0.1:9091"
            ).rstrip("/"),
            backup_catalog_file=Path(
                require_environment("SECURITY_RELAY_BACKUP_CATALOG_FILE")
            ),
            hmac_secret_file=credential_directory / "grafana-webhook-hmac",
            ca_file=Path(require_environment("SECURITY_RELAY_CA_FILE")),
        )
        for endpoint in (settings.thehive_url, settings.opencti_url):
            parsed = urllib.parse.urlparse(endpoint)
            if parsed.scheme != "https" or not parsed.hostname:
                raise ValueError(
                    f"integration endpoint must be an HTTPS URL: {endpoint!r}"
                )
        for name, endpoint in (
            ("SECURITY_RELAY_LOKI_URL", settings.loki_url),
            ("SECURITY_RELAY_PROMETHEUS_URL", settings.prometheus_url),
        ):
            parsed = urllib.parse.urlparse(endpoint)
            if parsed.scheme != "http" or parsed.hostname not in {
                "127.0.0.1",
                "localhost",
                "::1",
            }:
                raise ValueError(f"{name} must be a loopback HTTP URL")
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


def load_backup_catalog(path: Path) -> list[dict[str, Any]]:
    """Load and bound the trusted, declarative service recovery contract."""
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"invalid backup catalog: {error}") from error
    if not isinstance(value, list) or not 1 <= len(value) <= 64:
        raise ValueError("backup catalog must contain between 1 and 64 datasets")

    catalog: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for item in value:
        if not isinstance(item, dict):
            raise ValueError("backup catalog entries must be objects")
        dataset_id = str(item.get("id") or "")
        host = str(item.get("host") or "")
        metric_host = str(item.get("metricHost") or host)
        metric_dataset = str(item.get("metricDataset") or host)
        services = item.get("services")
        protection = str(item.get("protection") or "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", dataset_id):
            raise ValueError(f"invalid backup dataset id: {dataset_id!r}")
        if dataset_id in seen_ids:
            raise ValueError(f"duplicate backup dataset id: {dataset_id}")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", host):
            raise ValueError(f"invalid backup host: {host!r}")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", metric_host):
            raise ValueError(f"invalid backup metric host: {metric_host!r}")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", metric_dataset):
            raise ValueError(f"invalid backup metric dataset: {metric_dataset!r}")
        if (
            not isinstance(services, list)
            or not 1 <= len(services) <= 32
            or not all(isinstance(service, str) and service for service in services)
        ):
            raise ValueError(f"invalid services for backup dataset {dataset_id}")
        if protection not in {"off-host-restic", "external-unverified"}:
            raise ValueError(f"invalid protection for backup dataset {dataset_id}")

        backup_timer = item.get("backupTimer")
        restore_timer = item.get("restoreTimer")
        for name, timer in (
            ("backupTimer", backup_timer),
            ("restoreTimer", restore_timer),
        ):
            if timer is not None and (
                not isinstance(timer, str)
                or not re.fullmatch(r"[A-Za-z0-9_.@:-]{1,160}", timer)
            ):
                raise ValueError(f"invalid {name} for backup dataset {dataset_id}")
        try:
            max_age_hours = float(item.get("maxAgeHours"))
            restore_max_age_hours = float(item.get("restoreMaxAgeHours"))
        except (TypeError, ValueError) as error:
            raise ValueError(f"invalid recovery age for {dataset_id}") from error
        if not 1 <= max_age_hours <= 720 or not 1 <= restore_max_age_hours <= 2160:
            raise ValueError(f"recovery age outside bounds for {dataset_id}")

        seen_ids.add(dataset_id)
        catalog.append(
            {
                "id": dataset_id,
                "host": host,
                "metric_host": metric_host,
                "metric_dataset": metric_dataset,
                "services": sorted(set(services))[:32],
                "protection": protection,
                "backup_timer": backup_timer,
                "restore_timer": restore_timer,
                "max_age_hours": max_age_hours,
                "restore_max_age_hours": restore_max_age_hours,
            }
        )
    return catalog


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


def normalize_indicator(value: str) -> str | None:
    candidate = value.strip().rstrip(".,;:!?)")
    try:
        address = ipaddress.ip_address(candidate)
    except ValueError:
        pass
    else:
        return address.compressed

    if HASH_RE.fullmatch(candidate):
        return candidate.lower()
    if CVE_RE.fullmatch(candidate):
        return candidate.upper()
    parsed = urllib.parse.urlparse(candidate)
    if parsed.scheme in {"http", "https"} and parsed.hostname:
        return candidate[:4096]
    if DOMAIN_RE.fullmatch(candidate):
        return candidate.lower().rstrip(".")
    return None


def parse_news_context_terms(payload: dict[str, Any]) -> list[ContextTerm]:
    """Validate model-extracted search keys before they can reach a backend."""
    if not isinstance(payload, dict):
        raise ValueError("news context body must be a JSON object")
    unknown = set(payload) - set(NEWS_CONTEXT_KINDS)
    if unknown:
        raise ValueError("unsupported news context fields")

    terms: list[ContextTerm] = []
    seen: set[str] = set()
    for kind in NEWS_CONTEXT_KINDS:
        values = payload.get(kind, [])
        if not isinstance(values, list):
            raise ValueError(f"{kind} must be an array")
        for raw_value in values:
            if not isinstance(raw_value, str):
                continue
            value = raw_value.strip()
            if kind == "vulnerabilities":
                value = value.upper() if CVE_RE.fullmatch(value) else ""
            elif kind == "techniques":
                value = value.upper() if TECHNIQUE_RE.fullmatch(value) else ""
            elif kind == "indicators":
                value = normalize_indicator(value) or ""
            elif not NEWS_NAME_RE.fullmatch(value) or len(value.split()) > 8:
                value = ""
            elif value.casefold() in GENERIC_NEWS_CONTEXT_TERMS:
                value = ""
            if not value:
                continue
            key = value.casefold()
            if key in seen:
                continue
            seen.add(key)
            terms.append(ContextTerm(kind=kind, value=value))
            if len(terms) >= MAX_NEWS_CONTEXT_TERMS:
                return terms
    if not terms:
        raise ValueError("news context request has no valid high-signal terms")
    return terms


def parse_ops_summary_request(payload: dict[str, Any]) -> str:
    """Accept only a named, bounded lookback; never caller-supplied queries."""
    if not isinstance(payload, dict):
        raise ValueError("operations summary body must be a JSON object")
    unknown = set(payload) - {"window"}
    if unknown:
        raise ValueError("unsupported operations summary fields")
    window = str(payload.get("window", "24h"))
    if window not in OPS_SUMMARY_WINDOWS:
        raise ValueError("window must be one of: " + ", ".join(OPS_SUMMARY_WINDOWS))
    return window


def finite_float(value: Any, default: float = 0.0) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    if parsed != parsed or parsed in {float("inf"), float("-inf")}:
        return default
    return parsed


def metric_value(result: dict[str, Any]) -> float:
    value = result.get("value", [0, 0])
    if not isinstance(value, list) or len(value) < 2:
        return 0.0
    return finite_float(value[1])


def service_slo_status(
    healthy: bool,
    availability_percent: float | None,
    latency_p95_seconds: float | None,
) -> str:
    """Classify current reachability and the bounded reliability window."""
    if not healthy:
        return "down"
    if availability_percent is None and latency_p95_seconds is None:
        return "unknown"
    if (
        availability_percent is not None
        and availability_percent < 99.0
        or latency_p95_seconds is not None
        and latency_p95_seconds >= 2.0
    ):
        return "breached"
    if (
        availability_percent is not None
        and availability_percent < 99.9
        or latency_p95_seconds is not None
        and latency_p95_seconds >= 1.0
    ):
        return "at_risk"
    return "met"


def short_instance(value: Any) -> str:
    rendered = str(value or "unknown")[:300]
    if "://" in rendered:
        parsed = urllib.parse.urlparse(rendered)
        return (parsed.hostname or rendered)[:120]
    host = rendered.rsplit(":", 1)[0]
    return host.removesuffix(".guildedthorn.arpa")[:120]


def canonical_match_text(value: str) -> str:
    return "".join(character for character in value.casefold() if character.isalnum())


def text_matches_term(text: str, term: ContextTerm) -> bool:
    if term.value.casefold() in text.casefold():
        return True
    canonical_term = canonical_match_text(term.value)
    return len(canonical_term) >= 4 and canonical_term in canonical_match_text(text)


def matching_term_values(text: str, terms: list[ContextTerm]) -> list[str]:
    return [term.value for term in terms if text_matches_term(text, term)]


def re2_escape_literal(value: str) -> str:
    return re.sub(r"([\\.^$|?*+(){}\[\]])", r"\\\1", value)


def build_loki_context_query(terms: list[ContextTerm]) -> str:
    pattern = "(?i)(" + "|".join(re2_escape_literal(term.value) for term in terms) + ")"
    return (
        f'{{job=~"{LOKI_CONTEXT_JOBS}"}} '
        f"|~ {json.dumps(pattern, separators=(',', ':'))}"
    )


def news_context_excerpt(line: str, matched_terms: list[str]) -> str:
    rendered = " ".join(line.replace("\x00", " ").split())
    positions = [
        rendered.casefold().find(term.casefold())
        for term in matched_terms
        if term.casefold() in rendered.casefold()
    ]
    position = min((item for item in positions if item >= 0), default=0)
    start = max(0, position - 180)
    end = min(len(rendered), position + 420)
    prefix = "…" if start else ""
    suffix = "…" if end < len(rendered) else ""
    return prefix + rendered[start:end] + suffix


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

    @staticmethod
    def _references(node: dict[str, Any]) -> list[str]:
        references = []
        for edge in node.get("externalReferences", {}).get("edges", []):
            reference = edge.get("node", {})
            rendered = (
                reference.get("url")
                or reference.get("external_id")
                or reference.get("source_name")
            )
            if rendered:
                references.append(str(rendered)[:300])
        return references[:5]

    @classmethod
    def _report(cls, node: dict[str, Any], matched_terms: list[str]) -> dict[str, Any]:
        return {
            "id": str(node.get("id", ""))[:128],
            "name": str(node.get("name", "Unnamed report"))[:300],
            "description": str(node.get("description") or "")[:1000],
            "published": node.get("published"),
            "report_types": [str(item)[:80] for item in node.get("report_types", [])][
                :8
            ],
            "confidence": node.get("confidence"),
            "creator": str(node.get("createdBy", {}).get("name") or "")[:200],
            "references": cls._references(node),
            "matched_terms": sorted(set(matched_terms)),
        }

    def correlate_news(
        self, terms: list[ContextTerm]
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str], list[str]]:
        query = """
          query ThornNewsContext($search: String!) {
            intrusionSets(first: 3, search: $search) {
              edges {
                node {
                  id
                  name
                  aliases
                  description
                  confidence
                  createdBy { name }
                  reports(first: 3) {
                    edges {
                      node {
                        id
                        name
                        description
                        published
                        report_types
                        confidence
                        createdBy { name }
                        externalReferences {
                          edges { node { source_name external_id url } }
                        }
                      }
                    }
                  }
                }
              }
            }
            reports(first: 3, search: $search) {
              edges {
                node {
                  id
                  name
                  description
                  published
                  report_types
                  confidence
                  createdBy { name }
                  externalReferences {
                    edges { node { source_name external_id url } }
                  }
                }
              }
            }
          }
        """
        intrusion_sets: dict[str, dict[str, Any]] = {}
        reports: dict[str, dict[str, Any]] = {}
        matched_terms: set[str] = set()
        errors = []

        for term in terms:
            try:
                _, response = self.client.post(
                    self.endpoint,
                    {"query": query, "variables": {"search": term.value}},
                )
                if response.get("errors"):
                    raise DeliveryError(
                        str(response["errors"][0].get("message", "GraphQL error"))
                    )
            except Exception as error:
                logging.warning("OpenCTI news lookup failed for %s: %s", term.value, error)
                errors.append(f"{term.value}: {str(error)[:180]}")
                continue

            data = response.get("data", {})
            for edge in data.get("intrusionSets", {}).get("edges", []):
                node = edge.get("node", {})
                identity_text = "\n".join(
                    [
                        str(node.get("name") or ""),
                        *[str(alias) for alias in node.get("aliases", [])],
                        str(node.get("description") or ""),
                    ]
                )
                if not text_matches_term(identity_text, term):
                    continue
                matched_terms.add(term.value)
                intrusion_set_id = str(node.get("id") or node.get("name") or term.value)
                existing = intrusion_sets.setdefault(
                    intrusion_set_id,
                    {
                        "id": str(node.get("id", ""))[:128],
                        "name": str(node.get("name", "Unnamed intrusion set"))[:300],
                        "aliases": [str(alias)[:160] for alias in node.get("aliases", [])][
                            :12
                        ],
                        "description": str(node.get("description") or "")[:1000],
                        "confidence": node.get("confidence"),
                        "creator": str(node.get("createdBy", {}).get("name") or "")[
                            :200
                        ],
                        "matched_terms": [],
                    },
                )
                existing["matched_terms"] = sorted(
                    set(existing["matched_terms"]) | {term.value}
                )
                for report_edge in node.get("reports", {}).get("edges", []):
                    report_node = report_edge.get("node", {})
                    report_id = str(
                        report_node.get("id") or report_node.get("name") or term.value
                    )
                    rendered = self._report(report_node, [term.value])
                    if report_id in reports:
                        rendered["matched_terms"] = sorted(
                            set(reports[report_id]["matched_terms"]) | {term.value}
                        )
                    reports[report_id] = rendered

            for edge in data.get("reports", {}).get("edges", []):
                node = edge.get("node", {})
                report_text = "\n".join(
                    [str(node.get("name") or ""), str(node.get("description") or "")]
                )
                if not text_matches_term(report_text, term):
                    continue
                matched_terms.add(term.value)
                report_id = str(node.get("id") or node.get("name") or term.value)
                rendered = self._report(node, [term.value])
                if report_id in reports:
                    rendered["matched_terms"] = sorted(
                        set(reports[report_id]["matched_terms"]) | {term.value}
                    )
                reports[report_id] = rendered

        return (
            list(intrusion_sets.values())[:12],
            list(reports.values())[:16],
            sorted(matched_terms),
            errors[:8],
        )


class PrometheusClient:
    def __init__(self, base_url: str):
        self.endpoint = base_url + "/api/v1/query"

    def query(self, expression: str) -> list[dict[str, Any]]:
        url = self.endpoint + "?" + urllib.parse.urlencode({"query": expression})
        request = urllib.request.Request(
            url,
            method="GET",
            headers={"User-Agent": "ThornixOS-security-relay/1"},
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            body = response.read(MAX_OPS_QUERY_RESPONSE_BYTES + 1)
        if len(body) > MAX_OPS_QUERY_RESPONSE_BYTES:
            raise DeliveryError("Prometheus operations response exceeded its byte limit")
        payload = json.loads(body)
        if payload.get("status") != "success":
            raise DeliveryError("Prometheus operations query did not succeed")
        result = payload.get("data", {}).get("result", [])
        if not isinstance(result, list):
            raise DeliveryError("Prometheus operations query returned an invalid vector")
        return [item for item in result[:MAX_OPS_VECTOR_RESULTS] if isinstance(item, dict)]


class LokiClient:
    def __init__(self, base_url: str):
        self.endpoint = base_url + "/loki/api/v1/query_range"
        self.instant_endpoint = base_url + "/loki/api/v1/query"

    def count(self, expression: str) -> int:
        url = self.instant_endpoint + "?" + urllib.parse.urlencode({"query": expression})
        request = urllib.request.Request(
            url,
            method="GET",
            headers={"User-Agent": "ThornixOS-security-relay/1"},
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read(MAX_OPS_QUERY_RESPONSE_BYTES + 1)
        if len(body) > MAX_OPS_QUERY_RESPONSE_BYTES:
            raise DeliveryError("Loki operations response exceeded its byte limit")
        payload = json.loads(body)
        if payload.get("status") != "success":
            raise DeliveryError("Loki operations query did not succeed")
        total = 0.0
        for result in payload.get("data", {}).get("result", [])[:MAX_OPS_VECTOR_RESULTS]:
            if isinstance(result, dict):
                total += metric_value(result)
        return max(0, round(total))

    def correlate_news(
        self, terms: list[ContextTerm]
    ) -> tuple[list[dict[str, Any]], list[str]]:
        query = build_loki_context_query(terms)
        url = self.endpoint + "?" + urllib.parse.urlencode(
            {
                "query": query,
                "since": NEWS_CONTEXT_LOOKBACK,
                "limit": str(MAX_NEWS_CONTEXT_HITS),
                "direction": "backward",
            }
        )
        request = urllib.request.Request(
            url,
            method="GET",
            headers={"User-Agent": "ThornixOS-security-relay/1"},
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            body = response.read(MAX_NEWS_CONTEXT_RESPONSE_BYTES + 1)
        if len(body) > MAX_NEWS_CONTEXT_RESPONSE_BYTES:
            raise DeliveryError("Loki context response exceeded its byte limit")
        payload = json.loads(body)
        if payload.get("status") != "success":
            raise DeliveryError("Loki context query did not succeed")

        hits = []
        matched_terms: set[str] = set()
        for result in payload.get("data", {}).get("result", []):
            labels = {
                key: str(result.get("stream", {}).get(key, ""))[:128]
                for key in SAFE_LOKI_LABELS
                if result.get("stream", {}).get(key)
            }
            for timestamp, line in result.get("values", []):
                if not isinstance(line, str):
                    continue
                matches = matching_term_values(line, terms)
                if not matches:
                    continue
                matched_terms.update(matches)
                try:
                    observed_at = dt.datetime.fromtimestamp(
                        int(timestamp) / 1_000_000_000,
                        tz=dt.timezone.utc,
                    ).isoformat()
                except (TypeError, ValueError, OverflowError):
                    observed_at = ""
                hits.append(
                    {
                        "observed_at": observed_at,
                        "labels": labels,
                        "matched_terms": matches,
                        "excerpt": news_context_excerpt(line, matches),
                    }
                )
                if len(hits) >= MAX_NEWS_CONTEXT_HITS:
                    return hits, sorted(matched_terms)
        return hits, sorted(matched_terms)


def build_ops_summary(
    prometheus: PrometheusClient,
    loki: LokiClient,
    window: str,
    *,
    now: float | None = None,
    backup_catalog: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Build a bounded operational snapshot from fixed local queries."""
    timestamp = time.time() if now is None else now
    errors: dict[str, str] = {}

    def prom(name: str, expression: str) -> list[dict[str, Any]]:
        try:
            return prometheus.query(expression)
        except Exception as error:
            logging.warning("Prometheus operations query %s failed: %s", name, error)
            errors[f"prometheus:{name}"] = str(error)[:240]
            return []

    def loki_count(name: str, expression: str) -> int:
        try:
            return loki.count(expression)
        except Exception as error:
            logging.warning("Loki operations query %s failed: %s", name, error)
            errors[f"loki:{name}"] = str(error)[:240]
            return 0

    def labels(result: dict[str, Any]) -> dict[str, Any]:
        value = result.get("metric", {})
        return value if isinstance(value, dict) else {}

    def positive_hosts(results: list[dict[str, Any]]) -> list[str]:
        return sorted(
            {
                short_instance(labels(result).get("instance"))
                for result in results
                if metric_value(result) > 0
            }
        )[:64]

    node_rows = prom("node-up", 'up{job="node"}')
    down_hosts = sorted(
        short_instance(labels(result).get("instance"))
        for result in node_rows
        if metric_value(result) < 1
    )[:64]

    failed_unit_rows = prom(
        "failed-units", 'node_systemd_unit_state{job="node",state="failed"} == 1'
    )
    failed_units = sorted(
        (
            {
                "host": short_instance(labels(result).get("instance")),
                "unit": str(labels(result).get("name") or "unknown")[:160],
            }
            for result in failed_unit_rows
        ),
        key=lambda item: (item["host"], item["unit"]),
    )[:64]

    disk_rows = prom(
        "root-disk",
        '100 * (1 - node_filesystem_avail_bytes{job="node",mountpoint="/"} '
        '/ node_filesystem_size_bytes{job="node",mountpoint="/"})',
    )
    root_disks = sorted(
        (
            {
                "host": short_instance(labels(result).get("instance")),
                "used_percent": round(metric_value(result), 1),
            }
            for result in disk_rows
        ),
        key=lambda item: (-item["used_percent"], item["host"]),
    )[:64]
    disk_attention = [item for item in root_disks if item["used_percent"] >= 75][
        :16
    ]

    memory_rows = prom(
        "memory",
        '100 * (1 - node_memory_MemAvailable_bytes{job="node"} '
        '/ node_memory_MemTotal_bytes{job="node"})',
    )
    memory_attention = sorted(
        (
            {
                "host": short_instance(labels(result).get("instance")),
                "used_percent": round(metric_value(result), 1),
            }
            for result in memory_rows
            if metric_value(result) >= 80
        ),
        key=lambda item: (-item["used_percent"], item["host"]),
    )[:16]

    probe_rows = prom(
        "service-probes",
        'probe_success{job="blackbox-http",service_id!=""}',
    )
    unavailable_services = sorted(
        str(labels(result).get("instance") or "unknown")[:300]
        for result in probe_rows
        if metric_value(result) < 1
    )[:64]
    latency_rows = prom(
        "service-latency",
        'probe_duration_seconds{job="blackbox-http",service_id!=""}',
    )
    availability_rows = prom(
        "service-availability",
        f'avg_over_time(probe_success{{job="blackbox-http",service_id!=""}}[{window}])',
    )
    latency_p95_rows = prom(
        "service-latency-p95",
        f'quantile_over_time(0.95, probe_duration_seconds{{job="blackbox-http",service_id!=""}}[{window}])',
    )
    slow_services = sorted(
        (
            {
                "url": str(labels(result).get("instance") or "unknown")[:300],
                "seconds": round(metric_value(result), 2),
            }
            for result in latency_rows
            if metric_value(result) >= 2
        ),
        key=lambda item: (-item["seconds"], item["url"]),
    )[:16]
    http_status_rows = prom(
        "service-http-status",
        'probe_http_status_code{job="blackbox-http",service_id!=""}',
    )

    tls_rows = prom(
        "tls-expiry",
        '(probe_ssl_earliest_cert_expiry{job="blackbox-http",service_id!=""} - time()) / 86400',
    )
    internal_tls = []
    external_tls = []
    for result in tls_rows:
        instance = str(labels(result).get("instance") or "")[:300]
        hostname = urllib.parse.urlparse(instance).hostname or ""
        entry = {
            "url": instance,
            "days_remaining": round(metric_value(result), 2),
        }
        if is_internal_acme_hostname(hostname):
            entry["hours_remaining"] = round(metric_value(result) * 24, 1)
            internal_tls.append(entry)
        else:
            external_tls.append(entry)
    internal_tls_attention = sorted(
        (item for item in internal_tls if item["hours_remaining"] <= 4),
        key=lambda item: item["hours_remaining"],
    )[:16]
    external_tls_attention = sorted(
        (item for item in external_tls if item["days_remaining"] <= 30),
        key=lambda item: item["days_remaining"],
    )[:16]

    latency_by_instance = {
        str(labels(result).get("instance") or "unknown")[:300]: round(
            metric_value(result), 3
        )
        for result in latency_rows
    }
    availability_by_instance = {
        str(labels(result).get("instance") or "unknown")[:300]: round(
            max(0.0, min(100.0, metric_value(result) * 100)), 3
        )
        for result in availability_rows
    }
    latency_p95_by_instance = {
        str(labels(result).get("instance") or "unknown")[:300]: round(
            max(0.0, metric_value(result)), 3
        )
        for result in latency_p95_rows
    }
    http_status_by_instance = {
        str(labels(result).get("instance") or "unknown")[:300]: int(
            metric_value(result)
        )
        for result in http_status_rows
    }
    tls_by_instance = {
        item["url"]: item["days_remaining"] for item in [*internal_tls, *external_tls]
    }
    service_catalog = []
    for result in probe_rows[:64]:
        metric = labels(result)
        instance = str(metric.get("instance") or "unknown")[:300]
        parsed = urllib.parse.urlparse(instance)
        fallback_id = re.sub(
            r"[^a-z0-9]+",
            "-",
            (parsed.hostname or short_instance(instance)).lower(),
        ).strip("-")[:64]
        healthy = metric_value(result) >= 1
        availability_percent = availability_by_instance.get(instance)
        latency_p95_seconds = latency_p95_by_instance.get(instance)
        service_catalog.append(
            {
                "id": str(metric.get("service_id") or fallback_id or "unknown")[:64],
                "name": str(
                    metric.get("service_name")
                    or parsed.hostname
                    or short_instance(instance)
                    or "Unknown"
                )[:120],
                "role": str(metric.get("service_role") or "Monitored endpoint")[:160],
                "host": str(
                    metric.get("service_host")
                    or parsed.hostname
                    or short_instance(instance)
                )[:120],
                "status": "healthy" if healthy else "unavailable",
                "healthy": healthy,
                "latency_seconds": latency_by_instance.get(instance),
                "availability_percent": availability_percent,
                "latency_p95_seconds": latency_p95_seconds,
                "slo_status": service_slo_status(
                    healthy,
                    availability_percent,
                    latency_p95_seconds,
                ),
                "http_status": http_status_by_instance.get(instance),
                "tls_days_remaining": tls_by_instance.get(instance),
                "probe_url": instance,
                "url": str(metric.get("service_url") or "")[:300],
                "icon": str(metric.get("service_icon") or "mdi:server-network")[:80],
                "launchable": str(metric.get("service_launchable") or "false").lower()
                == "true",
            }
        )
    service_catalog.sort(key=lambda item: (item["name"].casefold(), item["id"]))
    slo_attention = [
        {
            "id": item["id"],
            "name": item["name"],
            "status": item["slo_status"],
            "availability_percent": item["availability_percent"],
            "latency_p95_seconds": item["latency_p95_seconds"],
        }
        for item in service_catalog
        if item["slo_status"] in {"down", "breached", "at_risk"}
    ][:16]
    slowest_services = [
        {
            "id": item["id"],
            "name": item["name"],
            "latency_seconds": item["latency_seconds"],
            "latency_p95_seconds": item["latency_p95_seconds"],
        }
        for item in sorted(
            (
                item
                for item in service_catalog
                if item["latency_seconds"] is not None
            ),
            key=lambda item: (-item["latency_seconds"], item["name"].casefold()),
        )[:5]
    ]

    timer_observations: dict[tuple[str, str], float] = {}
    success_observations: dict[tuple[str, str], float] = {}
    restore_observations: dict[tuple[str, str], float] = {}
    if backup_catalog is None:
        backup_rows = prom(
            "backups",
            'node_systemd_timer_last_trigger_seconds{'
            'name=~"restic-backups-.*|postgresqlBackup-.*|thorn-backup-restore-test.timer"}',
        )
        for result in backup_rows:
            metric = labels(result)
            key = (
                short_instance(metric.get("instance")),
                str(metric.get("name") or "unknown")[:160],
            )
            timer_observations[key] = max(
                timer_observations.get(key, 0.0), metric_value(result)
            )
    else:
        for result in prom("backup-success", "thorn_backup_last_success_seconds"):
            metric = labels(result)
            key = (
                short_instance(metric.get("instance")),
                str(metric.get("dataset") or "unknown")[:64],
            )
            success_observations[key] = max(
                success_observations.get(key, 0.0), metric_value(result)
            )
        for result in prom(
            "backup-restore-success", "thorn_backup_restore_last_success_seconds"
        ):
            metric = labels(result)
            key = (
                short_instance(metric.get("instance")),
                str(metric.get("dataset") or "unknown")[:64],
            )
            restore_observations[key] = max(
                restore_observations.get(key, 0.0), metric_value(result)
            )

    def timer_age(metric_hosts: list[str], timer: str | None) -> float | None:
        if timer is None:
            return None
        last_trigger = max(
            (timer_observations.get((host, timer), 0.0) for host in metric_hosts),
            default=0.0,
        )
        if last_trigger <= 0:
            return None
        return max(0.0, (timestamp - last_trigger) / 3600)

    def success_age(
        observations: dict[tuple[str, str], float],
        metric_hosts: list[str],
        metric_dataset: str,
    ) -> float | None:
        last_success = max(
            (
                observations.get((host, metric_dataset), 0.0)
                for host in metric_hosts
            ),
            default=0.0,
        )
        if last_success <= 0:
            return None
        return max(0.0, (timestamp - last_success) / 3600)

    backups: list[dict[str, Any]] = []
    if backup_catalog is None:
        for (host, timer), last_trigger in timer_observations.items():
            if timer == "thorn-backup-restore-test.timer":
                continue
            age_hours = (
                None
                if last_trigger <= 0
                else max(0.0, (timestamp - last_trigger) / 3600)
            )
            backups.append(
                {
                    "host": host,
                    "timer": timer,
                    "age_hours": None if age_hours is None else round(age_hours, 1),
                    "stale": age_hours is None or age_hours > 36,
                }
            )
    else:
        for dataset in backup_catalog:
            host = dataset["host"]
            metric_hosts = list({host, dataset["metric_host"]})
            metric_dataset = dataset["metric_dataset"]
            backup_timer = dataset["backup_timer"]
            restore_timer = dataset["restore_timer"]
            backup_age = success_age(
                success_observations, metric_hosts, metric_dataset
            )
            restore_age = success_age(
                restore_observations, metric_hosts, metric_dataset
            )
            externally_unverified = dataset["protection"] == "external-unverified"
            backup_stale = (
                not externally_unverified
                and (
                    backup_age is None
                    or backup_age > dataset["max_age_hours"]
                )
            )
            restore_stale = (
                not externally_unverified
                and (
                    restore_age is None
                    or restore_age > dataset["restore_max_age_hours"]
                )
            )
            coverage_gap = (
                externally_unverified
                or backup_timer is None
                or restore_timer is None
            )
            status = "verified"
            if coverage_gap:
                status = "coverage_gap"
            elif backup_age is None:
                status = "backup_unverified"
            elif backup_stale:
                status = "backup_stale"
            elif restore_age is None:
                status = "restore_unverified"
            elif restore_stale:
                status = "restore_stale"
            backups.append(
                {
                    "id": dataset["id"],
                    "host": host,
                    "metric_host": dataset["metric_host"],
                    "metric_dataset": metric_dataset,
                    "services": dataset["services"],
                    "protection": dataset["protection"],
                    "timer": backup_timer,
                    "restore_timer": restore_timer,
                    "age_hours": None if backup_age is None else round(backup_age, 1),
                    "restore_age_hours": (
                        None if restore_age is None else round(restore_age, 1)
                    ),
                    "protected": not coverage_gap and not backup_stale,
                    "restore_verified": not coverage_gap and not restore_stale,
                    "coverage_gap": coverage_gap,
                    "stale": backup_stale,
                    "restore_stale": restore_stale,
                    "status": status,
                }
            )
    backups = sorted(
        backups,
        key=lambda item: (
            item.get("status") == "verified",
            not item["stale"],
            item["host"],
        ),
    )[:64]
    stale_backups = [item for item in backups if item["stale"]][:16]
    unverified_restores = [
        item for item in backups if item.get("restore_stale", False)
    ][:16]
    backup_coverage_gaps = [
        item for item in backups if item.get("coverage_gap", False)
    ][:16]

    deployment_rows = prom(
        "deployment-info", 'comin_deployment_info{status="done"} == 1'
    )
    commits: dict[str, list[str]] = {}
    host_commits: dict[str, str] = {}
    for result in deployment_rows:
        metric = labels(result)
        host = short_instance(metric.get("instance"))
        commit = str(metric.get("commit_id") or "unknown")[:40]
        host_commits[host] = commit
        commits.setdefault(commit, []).append(host)
    majority_commit = ""
    if commits:
        majority_commit = sorted(
            commits, key=lambda commit: (-len(commits[commit]), commit)
        )[0]
    drifted_hosts = sorted(
        host for host, commit in host_commits.items() if commit != majority_commit
    )[:64]
    deployment_failures = positive_hosts(
        prom("deployment-failed", "comin_last_deployment_failed")
    )
    build_failures = positive_hosts(
        prom("build-failed", "comin_last_build_failed + comin_last_eval_failed")
    )
    fetch_failures = positive_hosts(prom("fetch-failed", "comin_last_fetch_failed"))
    reboot_pending = positive_hosts(prom("reboot-pending", "comin_need_to_reboot"))

    security = {
        "window": window,
        "suricata_alerts": loki_count(
            "suricata",
            f'sum(count_over_time({{job="suricata"}} | json '
            f'| event_type = "alert" [{window}]))',
        ),
        "pfsense_high_alerts": loki_count(
            "pfsense-suricata",
            f'sum(count_over_time({{job="syslog",pfsense_log="suricata"}} '
            f'|~ "Priority: [12]" [{window}]))',
        ),
        "ssh_failures": loki_count(
            "ssh-failures",
            f'sum(count_over_time({{job="systemd-journal",unit="sshd.service"}} '
            f'|~ "Failed password|Invalid user" [{window}]))',
        ),
        "opencanary_interactions": loki_count(
            "opencanary",
            f'sum(count_over_time({{job="systemd-journal",host="lure",'
            f'unit!~"loki.service|grafana.service"}} | json | src_host != "" '
            f'[{window}]))',
        ),
        "crowdsec_scenarios": loki_count(
            "crowdsec",
            f'sum(count_over_time({{unit="crowdsec.service"}} '
            f'|~ "performed" [{window}]))',
        ),
        "zeek_notices": loki_count(
            "zeek-notices",
            f'sum(count_over_time({{job="zeek",zeek_log="notice"}} [{window}]))',
        ),
    }

    critical_actions: list[str] = []
    warning_actions: list[str] = []
    maintenance_actions: list[str] = []
    if down_hosts:
        critical_actions.append("Restore node exporters: " + ", ".join(down_hosts))
    if failed_units:
        rendered = ", ".join(
            f"{item['host']}/{item['unit']}" for item in failed_units[:6]
        )
        critical_actions.append("Repair failed units: " + rendered)
    if unavailable_services:
        critical_actions.append(
            "Restore unavailable endpoints: " + ", ".join(unavailable_services[:5])
        )
    for item in disk_attention:
        message = f"Free root disk on {item['host']} ({item['used_percent']:.1f}% used)"
        if item["used_percent"] >= 95:
            critical_actions.append(message)
        elif item["used_percent"] >= 85:
            warning_actions.append(message)
        else:
            maintenance_actions.append(message)
    for item in memory_attention:
        warning_actions.append(
            f"Review memory pressure on {item['host']} ({item['used_percent']:.1f}% used)"
        )
    if stale_backups:
        critical_actions.append(
            "Repair stale backups: "
            + ", ".join(f"{item['host']}/{item['timer']}" for item in stale_backups)
        )
    if unverified_restores:
        critical_actions.append(
            "Run or repair recovery tests: "
            + ", ".join(item["host"] for item in unverified_restores)
        )
    if backup_coverage_gaps:
        critical_actions.append(
            "Close backup coverage gaps: "
            + ", ".join(
                f"{item['host']} ({', '.join(item.get('services', []))})"
                for item in backup_coverage_gaps
            )
        )
    if internal_tls_attention:
        critical_actions.append("Internal ACME renewal has less than four hours remaining")
    if external_tls_attention:
        critical = [item for item in external_tls_attention if item["days_remaining"] <= 7]
        target = critical_actions if critical else warning_actions
        target.append("Renew expiring non-ACME certificates")
    if deployment_failures or build_failures:
        critical_actions.append(
            "Repair failed deployments/builds: "
            + ", ".join(sorted(set(deployment_failures + build_failures)))
        )
    if fetch_failures:
        warning_actions.append("Repair comin fetch: " + ", ".join(fetch_failures))
    if drifted_hosts:
        warning_actions.append("Resolve deployment drift: " + ", ".join(drifted_hosts))
    if reboot_pending:
        warning_actions.append("Schedule reboots: " + ", ".join(reboot_pending))
    if slow_services:
        warning_actions.append(
            "Review slow endpoints: "
            + ", ".join(short_instance(item["url"]) for item in slow_services[:5])
        )
    breached_slos = [
        item["name"] for item in service_catalog if item["slo_status"] == "breached"
    ]
    if breached_slos:
        warning_actions.append(
            "Review service reliability SLOs: " + ", ".join(breached_slos[:5])
        )
    if security["opencanary_interactions"]:
        critical_actions.append("Review OpenCanary interactions in Grafana/TheHive")
    if errors:
        warning_actions.append("Repair incomplete operator telemetry queries")

    action_items = [
        *({"severity": "critical", "message": item} for item in critical_actions),
        *({"severity": "warning", "message": item} for item in warning_actions),
        *({"severity": "maintenance", "message": item} for item in maintenance_actions),
    ][:20]
    status = "critical" if critical_actions else "warning" if warning_actions else "healthy"
    headline = (
        f"{len(critical_actions)} critical and {len(warning_actions)} warning action(s)"
        if status != "healthy"
        else "Fleet, deployment, backups, and service probes look healthy"
    )

    return {
        "generated_at": dt.datetime.fromtimestamp(
            timestamp, tz=dt.timezone.utc
        ).isoformat(),
        "window": window,
        "summary": {
            "status": status,
            "headline": headline,
            "action_count": len(action_items),
        },
        "actions": action_items,
        "fleet": {
            "node_targets": len(node_rows),
            "down_hosts": down_hosts,
            "failed_units": failed_units,
            "top_root_disks": root_disks[:8],
            "disk_attention": disk_attention,
            "memory_attention": memory_attention,
        },
        "services": {
            "window": window,
            "checked": len(probe_rows),
            "healthy": sum(1 for item in service_catalog if item["healthy"]),
            "slo_met": sum(
                1 for item in service_catalog if item["slo_status"] == "met"
            ),
            "slo_target": {
                "availability_percent": 99.9,
                "latency_p95_seconds": 1.0,
            },
            "slo_attention": slo_attention,
            "slowest": slowest_services,
            "unavailable": unavailable_services,
            "slow": slow_services,
            "internal_acme_attention": internal_tls_attention,
            "external_tls_attention": external_tls_attention,
            "catalog": service_catalog,
        },
        "maintenance": {
            "backups": backups,
            "stale_backups": stale_backups,
            "unverified_restores": unverified_restores,
            "backup_coverage_gaps": backup_coverage_gaps,
            "backup_coverage": {
                "datasets": len(backups),
                "protected": sum(
                    1 for item in backups if item.get("protected", not item["stale"])
                ),
                "restore_verified": sum(
                    1 for item in backups if item.get("restore_verified", False)
                ),
                "gaps": len(backup_coverage_gaps),
            },
        },
        "deployment": {
            "targets": len(host_commits),
            "majority_commit": majority_commit,
            "commit_groups": [
                {"commit": commit, "hosts": sorted(hosts)}
                for commit, hosts in sorted(
                    commits.items(), key=lambda item: (-len(item[1]), item[0])
                )
            ][:8],
            "drifted_hosts": drifted_hosts,
            "deployment_failures": deployment_failures,
            "build_failures": build_failures,
            "fetch_failures": fetch_failures,
            "reboot_pending": reboot_pending,
        },
        "security": security,
        "errors": errors,
    }


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
        "news_context_requests_total",
        "news_context_matches_total",
        "news_context_errors_total",
        "ops_summary_requests_total",
        "ops_summary_errors_total",
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
        self.loki = LokiClient(settings.loki_url)
        self.prometheus = PrometheusClient(settings.prometheus_url)
        self.backup_catalog = load_backup_catalog(settings.backup_catalog_file)
        self.state = StateStore(settings.state_file)
        self.hmac_secret = read_secret(settings.hmac_secret_file).encode("utf-8")
        self.metrics = Metrics()
        self.processing_lock = threading.Lock()

    def query_ops_summary(self, payload: dict[str, Any]) -> dict[str, Any]:
        window = parse_ops_summary_request(payload)
        self.metrics.increment("ops_summary_requests_total")
        result = build_ops_summary(
            self.prometheus,
            self.loki,
            window,
            backup_catalog=self.backup_catalog,
        )
        if result.get("errors"):
            self.metrics.increment("ops_summary_errors_total")
        self.metrics.success()
        return result

    def query_news_context(self, payload: dict[str, Any]) -> dict[str, Any]:
        terms = parse_news_context_terms(payload)
        self.metrics.increment("news_context_requests_total")

        intrusion_sets: list[dict[str, Any]] = []
        reports: list[dict[str, Any]] = []
        opencti_terms: list[str] = []
        errors: dict[str, list[str]] = {"opencti": [], "loki": []}
        try:
            intrusion_sets, reports, opencti_terms, opencti_errors = (
                self.opencti.correlate_news(terms)
            )
            errors["opencti"] = opencti_errors
            if opencti_errors:
                self.metrics.increment("news_context_errors_total")
        except Exception as error:
            logging.exception("OpenCTI news correlation failed")
            errors["opencti"] = [str(error)[:300]]
            self.metrics.increment("news_context_errors_total")

        siem_hits: list[dict[str, Any]] = []
        siem_terms: list[str] = []
        try:
            siem_hits, siem_terms = self.loki.correlate_news(terms)
        except Exception as error:
            logging.exception("Loki news correlation failed")
            errors["loki"] = [str(error)[:300]]
            self.metrics.increment("news_context_errors_total")

        matched_terms = sorted(set(opencti_terms) | set(siem_terms))
        evidence_count = len(intrusion_sets) + len(reports) + len(siem_hits)
        if evidence_count:
            self.metrics.increment("news_context_matches_total")
        self.metrics.success()
        return {
            "terms": [dataclasses.asdict(term) for term in terms],
            "opencti": {
                "intrusion_sets": intrusion_sets,
                "reports": reports,
            },
            "siem": {
                "lookback": NEWS_CONTEXT_LOOKBACK,
                "hits": siem_hits,
            },
            "summary": {
                "has_evidence": evidence_count > 0,
                "matched_terms": matched_terms,
                "intrusion_set_count": len(intrusion_sets),
                "report_count": len(reports),
                "siem_hit_count": len(siem_hits),
            },
            "errors": {key: value for key, value in errors.items() if value},
        }

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
            if self.path not in {"/grafana", "/news-context", "/ops-summary"}:
                self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            maximum = {
                "/news-context": MAX_NEWS_CONTEXT_BODY_BYTES,
                "/ops-summary": MAX_OPS_SUMMARY_BODY_BYTES,
            }.get(self.path, MAX_BODY_BYTES)
            if length <= 0 or length > maximum:
                self.send_json(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "invalid body size"}
                )
                return
            body = self.rfile.read(length)

            if self.path == "/news-context":
                try:
                    payload = json.loads(body)
                    result = relay.query_news_context(payload)
                except (json.JSONDecodeError, ValueError) as error:
                    self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(error)[:500]})
                    return
                except Exception as error:
                    logging.exception("news context request failed")
                    relay.metrics.increment("news_context_errors_total")
                    self.send_json(
                        HTTPStatus.BAD_GATEWAY, {"error": str(error)[:500]}
                    )
                    return
                self.send_json(HTTPStatus.OK, result)
                return

            if self.path == "/ops-summary":
                try:
                    payload = json.loads(body)
                    result = relay.query_ops_summary(payload)
                except (json.JSONDecodeError, ValueError) as error:
                    self.send_json(HTTPStatus.BAD_REQUEST, {"error": str(error)[:500]})
                    return
                except Exception as error:
                    logging.exception("operations summary request failed")
                    relay.metrics.increment("ops_summary_errors_total")
                    self.send_json(
                        HTTPStatus.BAD_GATEWAY, {"error": str(error)[:500]}
                    )
                    return
                self.send_json(HTTPStatus.OK, result)
                return

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
