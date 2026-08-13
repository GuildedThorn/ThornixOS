"""ipc-auditord — kernel IPC auditor for inari (eBPF, observe-only).

Event-driven companion to rpc-auditord: a bpftrace child process hooks
`security_socket_connect` (every connect(), all address families),
`inet_csk_accept` (server-side TCP accepts), and `security_socket_sendmsg`
(connectionless datagram egress). This daemon parses the sensor stream,
enriches events (exe/cmdline/user/container via /proc, server attribution
via a refreshed listener map), dedupes against a persisted baseline, and
journals an audit stream.

Local IPC (AF_UNIX, AF_NETLINK, loopback AF_INET) → kernel_connect.
Non-loopback AF_INET connect() / sendto() → **egress_connect /
egress_sendmsg** — first contact to a new (process, dest-ip) pair is a
warning. This is the C2-observability plane: reverse shells, HTTPS
beaconing, connected+connectionless UDP, DNS-to-external, and raw exfil
are all attributed to the originating pid/exe/container here, which
host-side flow tools (netmon, on the network plane) cannot attribute.
Port-zero connect probes are ignored: libc uses those to select a route and
source address while resolving names, but they never transmit application
traffic and otherwise dominate desktop telemetry.

Zero sampling gap: connections too short-lived for rpc-auditord's 10s
poll are still caught here, at the moment the kernel processes them.

Journald identifier is ipc-auditor; the Grafana query on the
"Loki Inari Journal" datasource is:  {identifier="ipc-auditor"} | json
(combined view with the poller: {identifier=~"rpc-auditor|ipc-auditor"})

Events:
  daemon_start / daemon_stop
  kernel_connect      dedup key = client exe|uid|dest; level=warning for
                      pairs unknown to the baseline after learning
  kernel_accept       server-side TCP accept (key = exe|uid|:port)
  sensor_exit         bpftrace child died (daemon exits; systemd restarts)
  drop_summary        hourly count of out-of-scope/rate-dropped events

Needs CAP_BPF+CAP_PERFMON (probe attach), CAP_SYS_PTRACE+DAC caps
(/proc enrichment), bpftrace + iproute2 on PATH — pinned by the unit.
State: /var/lib/ipc-auditor/state.json. Pure stdlib.
"""

import json
import os
import pwd
import re
import signal
import subprocess
import sys
import time

BT_SCRIPT     = os.environ.get("IPC_AUDIT_BT", "/etc/ipc-auditor/ipc-audit.bt")
STATE_FILE    = os.environ.get("IPC_AUDITOR_STATE",
                               "/var/lib/ipc-auditor/state.json")
RESEEN_TTL_S  = 6 * 3600     # re-log a known pair at most this often
LEARN_S       = 600          # no prior state: first 10 min = baseline
SAVE_EVERY_S  = 300
LISTENER_TTL  = 15           # listener-map refresh cadence
MAX_PER_MIN   = 300          # emit rate cap (drops are summarized hourly)
SUMMARY_S     = 3600

_LOOPBACK = ("127.", "[::1]", "::1", "0.0.0.0", "[::]")
EGRESS_TTL_S  = 3600         # re-log a repeated (proc,dest-ip) egress hourly
_DOCKER_RE = re.compile(r"docker[-/]([0-9a-f]{12})[0-9a-f]*(?:\.scope)?")


def _inet_target(dest: str) -> tuple[str, int | None]:
    """Split bpftrace's bare IPv4/IPv6 ``address:port`` representation."""
    ip, separator, port_text = dest.rpartition(":")
    if not separator:
        return dest.strip("[]"), None
    try:
        port = int(port_text)
    except ValueError:
        port = None
    return ip.strip("[]"), port


def _skip_egress_ip(ip: str) -> bool:
    """Noise never worth a C2 flag: loopback, link-local, multicast,
    broadcast, unspecified. Keeps ALL routable uni-cast (LAN + WAN).
    Handles bare IPv6 (bpftrace ntop emits no brackets)."""
    ip = ip.strip("[]")
    if ip.startswith("127.") or ip.startswith("169.254."):
        return True
    if ip in ("::1", "::", "0.0.0.0", "255.255.255.255"):
        return True
    if ip.startswith("fe80") or ip.startswith("ff"):     # v6 link-local/mcast
        return True
    head = ip.split(".", 1)[0]
    if head.isdigit() and 224 <= int(head) <= 239:       # v4 multicast /4
        return True
    return False


def _is_egress(kind: str, ip: str, port: int | None) -> bool:
    """Whether an inet sensor event can carry data beyond local scope."""
    return (
        kind in ("C", "S")
        and port not in (None, 0)
        and not _skip_egress_ip(ip)
    )


_USERS_RE = re.compile(r'users:\(\("([^"]+)",pid=(\d+),fd=\d+\)')
_PRIO = {"info": "6", "notice": "5", "warning": "4", "err": "3"}


def emit(level: str, event: str, **fields) -> None:
    doc = {"event": event, **fields}
    sys.stdout.write(f"<{_PRIO.get(level, '6')}>{json.dumps(doc, sort_keys=True)}\n")
    sys.stdout.flush()


def proc_extra(pid: int) -> dict:
    """exe/cmdline/container for a pid — best-effort (process may be gone)."""
    out = {}
    try:
        out["exe"] = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        pass
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmd = f.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
        if cmd:
            out["cmd"] = cmd[:200]
    except OSError:
        pass
    try:
        with open(f"/proc/{pid}/cgroup") as f:
            m = _DOCKER_RE.search(f.read())
        if m:
            out["container"] = m.group(1)
    except OSError:
        pass
    return out


def username(uid: int) -> str:
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


class Listeners:
    """dest (unix path / tcp port) → (server_exe, server_pid), refreshed
    from `ss` at most every LISTENER_TTL seconds, on demand."""

    def __init__(self):
        self.at = 0.0
        self.unix: dict = {}
        self.tcp: dict = {}

    def _refresh(self):
        self.unix, self.tcp = {}, {}
        try:
            out = subprocess.run(["ss", "-H", "-n", "-p", "-x", "-l"],
                                 capture_output=True, text=True, timeout=10)
            for ln in out.stdout.splitlines():
                t = ln.split()
                m = _USERS_RE.search(ln)
                if len(t) >= 5 and t[4] != "*" and m:
                    self.unix[t[4].rstrip("@")] = (m.group(1), int(m.group(2)))
            out = subprocess.run(["ss", "-H", "-n", "-p", "-t", "-l"],
                                 capture_output=True, text=True, timeout=10)
            for ln in out.stdout.splitlines():
                t = ln.split()
                m = _USERS_RE.search(ln)
                if len(t) >= 4 and m:
                    try:
                        port = int(t[3].rsplit(":", 1)[1])
                    except (IndexError, ValueError):
                        continue
                    self.tcp[port] = (m.group(1), int(m.group(2)))
        except Exception:  # noqa: BLE001 — attribution is best-effort
            pass
        self.at = time.monotonic()

    def lookup(self, transport: str, dest: str):
        if time.monotonic() - self.at > LISTENER_TTL:
            self._refresh()
        if transport == "unix":
            return self.unix.get(dest)
        try:
            return self.tcp.get(int(dest.rsplit(":", 1)[1]))
        except (IndexError, ValueError):
            return None


def load_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"pairs": {}}


def save_state(pairs: dict) -> None:
    tmp = STATE_FILE + ".tmp"
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump({"pairs": pairs}, f)
        os.replace(tmp, STATE_FILE)
    except OSError as e:
        emit("err", "state_save_failed", error=str(e))


def main() -> int:
    known = load_state()["pairs"]
    learning_until = time.time() + (LEARN_S if not known else 0)
    listeners = Listeners()
    self_pid = os.getpid()

    sensor = subprocess.Popen(
        ["bpftrace", BT_SCRIPT], text=True, bufsize=1,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    emit("info", "daemon_start", sensor_pid=sensor.pid,
         known_pairs=len(known), learning=bool(learning_until > time.time()))

    def _sig(*_a):
        sensor.terminate()

    signal.signal(signal.SIGTERM, _sig)
    signal.signal(signal.SIGINT, _sig)

    dropped = {"scope": 0, "rate": 0}
    minute = [int(time.time() // 60), 0]     # [minute bucket, emitted]
    last_save = last_summary = time.time()

    for line in sensor.stdout:
        line = line.rstrip("\n")
        if not line or line[0] not in "CAS":
            continue                          # bpftrace preamble / map output
        parts = line.split("|", 5)
        if len(parts) != 6:
            continue
        kind, fam, pid_s, uid_s, comm, dest = parts
        try:
            pid, uid = int(pid_s), int(uid_s)
        except ValueError:
            continue
        if pid in (self_pid, sensor.pid):
            continue                          # our own ss/sensor plumbing

        now = time.time()
        if fam == "unix" and not dest:
            dest = "@abstract"

        # classify — non-loopback routable inet (connect or sendto) is the
        # EGRESS / C2 plane; everything else is local IPC.
        is_inet = fam.startswith("inet")
        dest_ip, dest_port = _inet_target(dest) if is_inet else ("", None)
        # glibc and other runtimes connect() to resolved addresses with port
        # zero only to ask the kernel which route/source address it would use.
        # No packet can carry application data to TCP/UDP port zero, so these
        # probes are scope noise rather than egress evidence.
        egress = is_inet and _is_egress(kind, dest_ip, dest_port)

        if not egress and is_inet:
            # loopback inet connect() = local IPC (keep); loopback/noise
            # datagram or multicast/bcast connect = uninteresting (drop).
            if kind != "C" or not dest.startswith(_LOOPBACK):
                dropped["scope"] += 1
                continue

        if egress:
            key = f"{comm}|{uid}|E|{dest_ip}"
            ttl = EGRESS_TTL_S
        else:
            key = f"{comm}|{uid}|{kind}|{dest}"
            ttl = RESEEN_TTL_S

        fresh = key not in known
        if not fresh and now - known[key] < ttl:
            known[key] = now
        else:
            known[key] = now
            bucket = int(now // 60)
            if bucket != minute[0]:
                minute[:] = [bucket, 0]
            if minute[1] >= MAX_PER_MIN:
                dropped["rate"] += 1
            else:
                minute[1] += 1
                learning = now < learning_until
                level = "info" if (not fresh or learning) else "warning"
                extra = proc_extra(pid)
                doc = {"transport": fam, "dest": dest, "client_pid": pid,
                       "client_uid": uid, "client_user": username(uid),
                       "client_comm": comm,
                       "client_exe": extra.get("exe", comm),
                       "client_cmd": extra.get("cmd", ""),
                       "baseline": learning and fresh,
                       "new_pair": fresh and not learning}
                if "container" in extra:
                    doc["client_container"] = extra["container"]
                if egress:
                    doc["dest_ip"] = dest_ip
                    doc["dest_port"] = dest_port
                    doc["new_dest"] = fresh and not learning
                    emit(level, "egress_connect" if kind == "C"
                         else "egress_sendmsg", **doc)
                elif kind == "C":
                    srv = listeners.lookup("unix" if fam == "unix" else "tcp",
                                           dest) if fam != "netlink" else None
                    if srv:
                        doc["server_exe"], doc["server_pid"] = srv
                    emit(level, "kernel_connect", **doc)
                else:
                    emit(level, "kernel_accept", **doc)

        if now - last_save > SAVE_EVERY_S:
            save_state(known)
            last_save = now
        if now - last_summary > SUMMARY_S:
            emit("info", "drop_summary", **dropped)
            dropped = {"scope": 0, "rate": 0}
            last_summary = now

    rc = sensor.wait()
    save_state(known)
    if rc not in (0, -15):                    # -15 = our own SIGTERM
        emit("err", "sensor_exit", returncode=rc)
        emit("info", "daemon_stop", known_pairs=len(known))
        return 1
    emit("info", "daemon_stop", known_pairs=len(known))
    return 0


if __name__ == "__main__":
    sys.exit(main())
