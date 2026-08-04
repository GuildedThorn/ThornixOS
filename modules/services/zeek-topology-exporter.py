"""Build a bounded, rolling Prometheus topology snapshot from Zeek conn.log."""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import ipaddress
import json
import os
import signal
import tempfile
import time
from pathlib import Path
from typing import Callable


@dataclasses.dataclass(frozen=True)
class Node:
    id: str
    title: str
    subtitle: str
    role: str
    zone: str
    color: str


@dataclasses.dataclass
class Bucket:
    connections: int = 0
    bytes: int = 0
    packets: int = 0


@dataclasses.dataclass
class Edge:
    source: Node
    target: Node
    buckets: dict[int, Bucket] = dataclasses.field(default_factory=dict)
    last_seen: float = 0.0


@dataclasses.dataclass(frozen=True)
class EdgeSnapshot:
    edge: Edge
    connections: int
    bytes: int
    packets: int


ROLE_COLORS = {
    "firewall": "#E02F44",
    "hypervisor": "#8F3BB8",
    "storage": "#F2CC0C",
    "web": "#FF9830",
    "siem": "#56A64B",
    "workstation": "#5794F2",
    "lab": "#FF780A",
    "external": "#C4162A",
    "private-network": "#EAB839",
    "discovered": "#3274D9",
    "special": "#8E8E8E",
}


def number(value: object) -> int:
    if value is None or value == "-":
        return 0
    try:
        return max(0, int(float(value)))
    except (TypeError, ValueError):
        return 0


def label_escape(value: object) -> str:
    return str(value).replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def metric(name: str, labels: dict[str, object] | None, value: int | float) -> str:
    rendered_labels = ""
    if labels:
        rendered_labels = "{" + ",".join(
            f'{key}="{label_escape(labels[key])}"' for key in sorted(labels)
        ) + "}"
    return f"{name}{rendered_labels} {value}"


class Topology:
    def __init__(
        self,
        *,
        local_networks: list[str],
        known_hosts: dict[str, dict[str, str]],
        window_seconds: int,
        bucket_seconds: int,
        max_nodes: int,
        max_edges: int,
    ) -> None:
        self.local_networks = [ipaddress.ip_network(network) for network in local_networks]
        self.known_hosts = self._validate_known_hosts(known_hosts)
        self.window_seconds = window_seconds
        self.bucket_seconds = bucket_seconds
        self.max_nodes = max_nodes
        self.max_edges = max_edges
        self.edges: dict[tuple[str, str], Edge] = {}
        self.started_at = time.time()
        self.last_event_timestamp = 0.0
        self.observed_connections = 0
        self.parse_errors = 0
        self.timestamp_errors = 0
        self.evicted_edges = 0
        self.file_available = False

    @staticmethod
    def _validate_known_hosts(
        known_hosts: dict[str, dict[str, str]],
    ) -> dict[ipaddress._BaseAddress, dict[str, str]]:
        validated: dict[ipaddress._BaseAddress, dict[str, str]] = {}
        ids: set[str] = set()
        for raw_ip, metadata in known_hosts.items():
            address = ipaddress.ip_address(raw_ip)
            title = metadata.get("title", "").strip()
            if not title:
                raise ValueError(f"known host {raw_ip} has an empty title")
            node_id = metadata.get("id", title).strip()
            if not node_id:
                raise ValueError(f"known host {raw_ip} has an empty id")
            if node_id in ids:
                raise ValueError(f"known host id is not unique: {node_id}")
            ids.add(node_id)
            validated[address] = {
                "id": node_id,
                "title": title,
                "role": metadata.get("role", "discovered").strip() or "discovered",
                "color": metadata.get("color", "").strip(),
            }
        return validated

    def _is_local(self, address: ipaddress._BaseAddress) -> bool:
        return any(
            address.version == network.version and address in network
            for network in self.local_networks
        )

    def node_for(self, raw_address: object) -> Node:
        address = ipaddress.ip_address(str(raw_address))
        known = self.known_hosts.get(address)
        if known is not None:
            role = known["role"]
            return Node(
                id=known["id"],
                title=known["title"],
                subtitle=f"{role} · {address}",
                role=role,
                zone="OPT1" if self._is_local(address) else "known",
                color=known["color"] or ROLE_COLORS.get(role, "blue"),
            )

        if self._is_local(address):
            return Node(
                id=str(address),
                title=str(address),
                subtitle="discovered OPT1 host",
                role="discovered",
                zone="OPT1",
                color=ROLE_COLORS["discovered"],
            )

        # Public peers are intentionally one node. Keeping every transient CDN
        # or scanner IP as a Prometheus label would grow the 90-day TSDB forever.
        if address.is_global:
            return Node(
                id="internet",
                title="Internet",
                subtitle="aggregated public peers",
                role="external",
                zone="Internet",
                color=ROLE_COLORS["external"],
            )

        if address.is_private:
            return Node(
                id="other-private",
                title="Other private networks",
                subtitle="aggregated non-OPT1 RFC1918 peers",
                role="private-network",
                zone="Private",
                color=ROLE_COLORS["private-network"],
            )

        return Node(
            id="special-addresses",
            title="Special addresses",
            subtitle="loopback, link-local, multicast, or reserved",
            role="special",
            zone="Special",
            color=ROLE_COLORS["special"],
        )

    def _purge_edge(self, edge: Edge, now: float) -> None:
        oldest_bucket = int((now - self.window_seconds) // self.bucket_seconds)
        for bucket_id in list(edge.buckets):
            if bucket_id < oldest_bucket:
                del edge.buckets[bucket_id]

    def purge(self, now: float) -> None:
        for key, edge in list(self.edges.items()):
            self._purge_edge(edge, now)
            if not edge.buckets:
                del self.edges[key]

    def _evict_one_edge(self, now: float) -> None:
        self.purge(now)
        if len(self.edges) < self.max_edges:
            return
        victim = min(
            self.edges,
            key=lambda key: (
                self.edges[key].last_seen,
                sum(bucket.connections for bucket in self.edges[key].buckets.values()),
            ),
        )
        del self.edges[victim]
        self.evicted_edges += 1

    def ingest(self, record: dict[str, object], now: float | None = None) -> None:
        current_time = time.time() if now is None else now
        try:
            source = self.node_for(record.get("id.orig_h", record.get("id_orig_h")))
            target = self.node_for(record.get("id.resp_h", record.get("id_resp_h")))
        except (TypeError, ValueError):
            self.parse_errors += 1
            return

        try:
            event_time = float(record.get("ts", current_time))
        except (TypeError, ValueError):
            event_time = current_time
            self.timestamp_errors += 1

        # Ignore stale bootstrap records and clamp clocks that are implausibly
        # ahead. Neither condition gets to keep buckets alive indefinitely.
        if event_time < current_time - self.window_seconds:
            return
        if event_time > current_time + 60:
            event_time = current_time
            self.timestamp_errors += 1

        key = (source.id, target.id)
        edge = self.edges.get(key)
        if edge is None:
            self._evict_one_edge(current_time)
            edge = Edge(source=source, target=target)
            self.edges[key] = edge

        bucket_id = int(event_time // self.bucket_seconds)
        bucket = edge.buckets.setdefault(bucket_id, Bucket())
        bucket.connections += 1
        bucket.bytes += (
            number(record.get("orig_bytes")) + number(record.get("resp_bytes"))
        )
        bucket.packets += (
            number(record.get("orig_pkts")) + number(record.get("resp_pkts"))
        )
        edge.last_seen = max(edge.last_seen, event_time)
        self.last_event_timestamp = max(self.last_event_timestamp, event_time)
        self.observed_connections += 1

    def snapshot(self, now: float | None = None) -> tuple[list[EdgeSnapshot], dict[str, dict[str, object]]]:
        current_time = time.time() if now is None else now
        self.purge(current_time)

        candidates: list[EdgeSnapshot] = []
        for edge in self.edges.values():
            candidates.append(
                EdgeSnapshot(
                    edge=edge,
                    connections=sum(bucket.connections for bucket in edge.buckets.values()),
                    bytes=sum(bucket.bytes for bucket in edge.buckets.values()),
                    packets=sum(bucket.packets for bucket in edge.buckets.values()),
                )
            )
        candidates.sort(
            key=lambda item: (item.connections, item.bytes, item.edge.last_seen),
            reverse=True,
        )

        selected: list[EdgeSnapshot] = []
        node_ids: set[str] = set()
        for candidate in candidates:
            required = node_ids | {candidate.edge.source.id, candidate.edge.target.id}
            if len(required) > self.max_nodes:
                continue
            selected.append(candidate)
            node_ids = required
            if len(selected) >= self.max_edges:
                break

        nodes: dict[str, dict[str, object]] = {}
        for candidate in selected:
            for node, direction in (
                (candidate.edge.source, "out"),
                (candidate.edge.target, "in"),
            ):
                stats = nodes.setdefault(
                    node.id,
                    {
                        "node": node,
                        "bytes_in": 0,
                        "bytes_out": 0,
                        "connections_in": 0,
                        "connections_out": 0,
                    },
                )
                stats[f"bytes_{direction}"] = int(stats[f"bytes_{direction}"]) + candidate.bytes
                stats[f"connections_{direction}"] = int(
                    stats[f"connections_{direction}"]
                ) + candidate.connections
        return selected, nodes

    @staticmethod
    def _edge_color(source: Node, target: Node) -> str:
        if source.zone == "Internet":
            return "#E02F44"
        if target.zone == "Internet":
            return "#3274D9"
        if source.zone == "OPT1" and target.zone == "OPT1":
            return "#56A64B"
        return "#FF9830"

    def render(self, now: float | None = None) -> str:
        current_time = time.time() if now is None else now
        edges, nodes = self.snapshot(current_time)
        lines = [
            "# HELP thorn_topology_exporter_info Whether the topology exporter rendered successfully.",
            "# TYPE thorn_topology_exporter_info gauge",
            metric("thorn_topology_exporter_info", None, 1),
            "# HELP thorn_topology_window_seconds Rolling topology window in seconds.",
            "# TYPE thorn_topology_window_seconds gauge",
            metric("thorn_topology_window_seconds", None, self.window_seconds),
            "# HELP thorn_topology_last_render_timestamp_seconds Unix time of the latest snapshot.",
            "# TYPE thorn_topology_last_render_timestamp_seconds gauge",
            metric("thorn_topology_last_render_timestamp_seconds", None, current_time),
            "# HELP thorn_topology_last_event_timestamp_seconds Unix time of the newest accepted Zeek connection.",
            "# TYPE thorn_topology_last_event_timestamp_seconds gauge",
            metric(
                "thorn_topology_last_event_timestamp_seconds",
                None,
                self.last_event_timestamp,
            ),
            "# HELP thorn_topology_conn_log_available Whether Zeek conn.log is readable.",
            "# TYPE thorn_topology_conn_log_available gauge",
            metric("thorn_topology_conn_log_available", None, int(self.file_available)),
            "# HELP thorn_topology_active_nodes Number of nodes in the rendered graph.",
            "# TYPE thorn_topology_active_nodes gauge",
            metric("thorn_topology_active_nodes", None, len(nodes)),
            "# HELP thorn_topology_active_edges Number of edges in the rendered graph.",
            "# TYPE thorn_topology_active_edges gauge",
            metric("thorn_topology_active_edges", None, len(edges)),
            "# HELP thorn_topology_observed_connections_total Accepted Zeek connection records since exporter start.",
            "# TYPE thorn_topology_observed_connections_total counter",
            metric(
                "thorn_topology_observed_connections_total",
                None,
                self.observed_connections,
            ),
            "# HELP thorn_topology_parse_errors_total Zeek records rejected because an address was invalid.",
            "# TYPE thorn_topology_parse_errors_total counter",
            metric("thorn_topology_parse_errors_total", None, self.parse_errors),
            "# HELP thorn_topology_timestamp_errors_total Zeek records with an invalid or future timestamp.",
            "# TYPE thorn_topology_timestamp_errors_total counter",
            metric(
                "thorn_topology_timestamp_errors_total",
                None,
                self.timestamp_errors,
            ),
            "# HELP thorn_topology_evicted_edges_total Edges evicted to enforce the memory bound.",
            "# TYPE thorn_topology_evicted_edges_total counter",
            metric("thorn_topology_evicted_edges_total", None, self.evicted_edges),
            "# HELP thorn_topology_edge_connections Connections on a directed edge in the rolling window.",
            "# TYPE thorn_topology_edge_connections gauge",
        ]

        for candidate in edges:
            source = candidate.edge.source
            target = candidate.edge.target
            edge_hash = hashlib.blake2s(
                f"{source.id}\0{target.id}".encode(), digest_size=8
            ).hexdigest()
            labels = {
                "id": f"edge-{edge_hash}",
                "source": source.id,
                "target": target.id,
                "color": self._edge_color(source, target),
                "detail__source_zone": source.zone,
                "detail__target_zone": target.zone,
            }
            lines.append(metric("thorn_topology_edge_connections", labels, candidate.connections))

        lines.extend(
            [
                "# HELP thorn_topology_edge_bytes Bytes on a directed edge in the rolling window.",
                "# TYPE thorn_topology_edge_bytes gauge",
            ]
        )
        for candidate in edges:
            source = candidate.edge.source
            target = candidate.edge.target
            labels = {"source": source.id, "target": target.id}
            lines.append(metric("thorn_topology_edge_bytes", labels, candidate.bytes))

        lines.extend(
            [
                "# HELP thorn_topology_edge_packets Packets on a directed edge in the rolling window.",
                "# TYPE thorn_topology_edge_packets gauge",
            ]
        )
        for candidate in edges:
            source = candidate.edge.source
            target = candidate.edge.target
            labels = {"source": source.id, "target": target.id}
            lines.append(metric("thorn_topology_edge_packets", labels, candidate.packets))

        lines.extend(
            [
                "# HELP thorn_topology_node_bytes Traffic associated with a node in the rolling window.",
                "# TYPE thorn_topology_node_bytes gauge",
            ]
        )
        for node_id in sorted(nodes):
            stats = nodes[node_id]
            node = stats["node"]
            assert isinstance(node, Node)
            total_bytes = int(stats["bytes_in"]) + int(stats["bytes_out"])
            labels = {
                "id": node.id,
                "title": node.title,
                "subTitle": node.subtitle,
                "color": node.color,
                "detail__role": node.role,
                "detail__zone": node.zone,
            }
            lines.append(metric("thorn_topology_node_bytes", labels, total_bytes))

        return "\n".join(lines) + "\n"


class ConnLogTailer:
    def __init__(self, path: Path, bootstrap_bytes: int) -> None:
        self.path = path
        self.bootstrap_bytes = bootstrap_bytes
        self.file = None
        self.inode: tuple[int, int] | None = None
        self.available = False

    def _open(self, *, bootstrap: bool) -> bool:
        try:
            file = self.path.open("rb")
            stat = os.fstat(file.fileno())
            if bootstrap and stat.st_size > self.bootstrap_bytes:
                file.seek(stat.st_size - self.bootstrap_bytes)
                file.readline()
            self.file = file
            self.inode = (stat.st_dev, stat.st_ino)
            self.available = True
            return True
        except OSError:
            self.available = False
            return False

    def _check_rotation(self) -> None:
        if self.file is None:
            return
        try:
            current = self.path.stat()
            current_inode = (current.st_dev, current.st_ino)
            if current_inode != self.inode:
                self.file.close()
                self.file = None
                self.inode = None
                self._open(bootstrap=False)
            elif current.st_size < self.file.tell():
                self.file.seek(0)
        except OSError:
            self.available = False

    def read(self, callback: Callable[[bytes], None], limit: int = 5000) -> int:
        if self.file is None and not self._open(bootstrap=True):
            return 0

        assert self.file is not None
        count = 0
        while count < limit:
            line = self.file.readline()
            if not line:
                break
            callback(line)
            count += 1
        if count < limit:
            self._check_rotation()
        return count


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as temporary:
            temporary_name = temporary.name
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, path)
    finally:
        if temporary_name is not None and os.path.exists(temporary_name):
            os.unlink(temporary_name)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--known-hosts", type=Path, required=True)
    parser.add_argument("--local-network", action="append", required=True)
    parser.add_argument("--window-seconds", type=int, default=300)
    parser.add_argument("--bucket-seconds", type=int, default=10)
    parser.add_argument("--max-nodes", type=int, default=128)
    parser.add_argument("--max-edges", type=int, default=256)
    parser.add_argument("--render-interval", type=float, default=5.0)
    parser.add_argument("--bootstrap-bytes", type=int, default=16 * 1024 * 1024)
    parser.add_argument("--once", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()
    if args.window_seconds < args.bucket_seconds * 2:
        raise SystemExit("window must contain at least two buckets")
    if args.max_nodes < 2 or args.max_edges < 1:
        raise SystemExit("max-nodes must be >= 2 and max-edges must be >= 1")

    known_hosts = json.loads(args.known_hosts.read_text(encoding="utf-8"))
    topology = Topology(
        local_networks=args.local_network,
        known_hosts=known_hosts,
        window_seconds=args.window_seconds,
        bucket_seconds=args.bucket_seconds,
        max_nodes=args.max_nodes,
        max_edges=args.max_edges,
    )
    tailer = ConnLogTailer(args.input, args.bootstrap_bytes)

    running = True

    def stop(_signum: int, _frame: object) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def ingest_line(raw_line: bytes) -> None:
        try:
            record = json.loads(raw_line)
            if not isinstance(record, dict):
                raise ValueError("connection record is not an object")
            topology.ingest(record)
        except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
            topology.parse_errors += 1

    next_render = 0.0
    while running:
        read_count = tailer.read(ingest_line)
        topology.file_available = tailer.available
        now = time.time()
        if now >= next_render:
            write_atomic(args.output, topology.render(now))
            next_render = now + args.render_interval
        if args.once and read_count == 0:
            break
        if read_count == 0:
            time.sleep(min(0.25, max(0.01, next_render - now)))

    write_atomic(args.output, topology.render())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
