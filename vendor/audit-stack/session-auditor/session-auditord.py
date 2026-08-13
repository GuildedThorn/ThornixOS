"""session-auditord — remote session & RCE auditor for inari (observe-only).

Third layer of the local audit family (rpc-auditor = RPC poller,
ipc-auditor = kernel eBPF sensor): this daemon watches the REMOTE
interaction plane — authentication, sessions, tunnels, and remote code
execution, trusted or otherwise. Touchstone-approved activity is
recorded like everything else: the audit stream is the record, not the
gate.

Three watchers feed one journald audit stream (identifier
session-auditor → Alloy → prod Loki tenant inari-journal → Grafana
"Loki Inari Journal": {identifier="session-auditor"} | json):

  journal follow   sshd Accepted/Failed/Invalid, sudo/su privileged
                   exec lines, pvedaemon auth + `starting task UPID`
  poll (10s)       logind session lifecycle (remote host/service/tty via
                   loginctl), inbound :22 flows, outbound ssh-client
                   flows, sshd/ssh-owned forward listeners (reverse &
                   local tunnels), cloudflared :7844 tunnel egress
  docker events    exec_create on containers (container RCE)

Events: auth_success auth_failure priv_exec remote_task session_new
session_closed inbound_ssh_conn outbound_ssh_conn tunnel_listener_new
tunnel_listener_gone tunnel_egress container_exec daemon_start
daemon_stop watcher_failed rate_overflow

Levels: auth_failure/tunnel_listener_new = warning; remote session_new,
auth_success (remote), priv_exec, container_exec, inbound_ssh_conn =
notice; the rest info. Repeat flow events dedupe on a persisted 1h TTL.

Needs uid 0 with CAP_SYS_PTRACE + CAP_DAC_READ_SEARCH + CAP_DAC_OVERRIDE
(journal read, /proc enrichment, docker.sock). iproute2 + systemd +
docker CLIs pinned on PATH by the unit. State:
/var/lib/session-auditor/state.json. Pure stdlib.
"""

import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time

STATE_FILE   = os.environ.get("SESSION_AUDITOR_STATE",
                              "/var/lib/session-auditor/state.json")
POLL_S       = 10
CONN_TTL_S   = 3600          # re-log a repeated flow at most hourly
MAX_PER_MIN  = 120
OUR_IDS      = {"session-auditor", "rpc-auditor", "ipc-auditor"}

_PRIO = {"info": "6", "notice": "5", "warning": "4", "err": "3"}
_LOOPBACK = ("127.", "[::1]", "::1")

SSH_ACCEPT  = re.compile(r"^Accepted (\S+) for (\S+) from (\S+) port (\d+)")
SSH_FAIL    = re.compile(r"^Failed (\S+) for (?:invalid user )?(\S+) from (\S+)")
SSH_INVALID = re.compile(r"^Invalid user (\S+) from (\S+)")
SUDO_LINE   = re.compile(
    r"^\s*(\S+) : .*?TTY=(\S+)\s*;\s*PWD=([^;]*);\s*USER=(\S+)\s*;\s*COMMAND=(.*)$")
SU_LINE     = re.compile(r"\(to (\S+)\) (\S+) on")
PVE_TASK    = re.compile(r"<([^>]+)> starting task (UPID:\S+)")
PVE_AUTH_OK = re.compile(r"successful auth for user '([^']+)'")
PVE_AUTH_NO = re.compile(r"authentication failure; rhost=(\S*) user=(\S+)")
_USERS_RE   = re.compile(r'users:\(\("([^"]+)",pid=(\d+),fd=\d+\)')

_emit_lock = threading.Lock()
_minute = [0, 0, 0]          # bucket, emitted, dropped


def emit(level: str, event: str, **fields) -> None:
    with _emit_lock:
        now_m = int(time.time() // 60)
        if now_m != _minute[0]:
            if _minute[2]:
                doc = {"event": "rate_overflow", "dropped": _minute[2]}
                sys.stdout.write(f"<4>{json.dumps(doc)}\n")
            _minute[:] = [now_m, 0, 0]
        if _minute[1] >= MAX_PER_MIN:
            _minute[2] += 1
            return
        _minute[1] += 1
        doc = {"event": event, **fields}
        sys.stdout.write(
            f"<{_PRIO.get(level, '6')}>{json.dumps(doc, sort_keys=True)}\n")
        sys.stdout.flush()


class State:
    """Persisted dedupe TTLs + known session/listener/tunnel sets."""

    def __init__(self):
        self.lock = threading.Lock()
        try:
            with open(STATE_FILE) as f:
                d = json.load(f)
        except (OSError, ValueError):
            d = {}
        self.dedupe: dict = d.get("dedupe", {})
        self.sessions: set = set(d.get("sessions", []))
        self.listeners: set = set(d.get("listeners", []))
        self.tunnel: list = d.get("tunnel", [])
        self.first_run = not d

    def fresh(self, key: str, ttl: float = CONN_TTL_S) -> bool:
        now = time.time()
        with self.lock:
            last = self.dedupe.get(key, 0)
            self.dedupe[key] = now
            return now - last > ttl

    def save(self):
        with self.lock:
            doc = {"dedupe": {k: v for k, v in self.dedupe.items()
                              if time.time() - v < 2 * CONN_TTL_S},
                   "sessions": sorted(self.sessions),
                   "listeners": sorted(self.listeners),
                   "tunnel": self.tunnel}
        tmp = STATE_FILE + ".tmp"
        try:
            os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
            with open(tmp, "w") as f:
                json.dump(doc, f)
            os.replace(tmp, STATE_FILE)
        except OSError as e:
            emit("err", "state_save_failed", error=str(e))


# ── Watcher 1: journald follow ───────────────────────────────────────────────

def classify_journal(e: dict) -> None:
    ident = e.get("SYSLOG_IDENTIFIER", "")
    msg = e.get("MESSAGE", "")
    if ident in OUR_IDS or not isinstance(msg, str):
        return
    host = e.get("_HOSTNAME", socket.gethostname())

    if ident == "sshd" or ident == "sshd-session":
        m = SSH_ACCEPT.match(msg)
        if m:
            emit("notice", "auth_success", service="ssh", method=m.group(1),
                 user=m.group(2), rhost=m.group(3), port=int(m.group(4)),
                 host=host)
            return
        m = SSH_FAIL.match(msg)
        if m:
            emit("warning", "auth_failure", service="ssh", method=m.group(1),
                 user=m.group(2), rhost=m.group(3),
                 invalid="invalid user" in msg, host=host)
            return
        m = SSH_INVALID.match(msg)
        if m:
            emit("warning", "auth_failure", service="ssh", method="pre-auth",
                 user=m.group(1), rhost=m.group(2), invalid=True, host=host)
        return
    if ident == "sudo":
        m = SUDO_LINE.match(msg)
        if m:
            emit("notice", "priv_exec", via="sudo", invoker=m.group(1),
                 tty=m.group(2), pwd=m.group(3).strip(),
                 target_user=m.group(4), command=m.group(5)[:300])
        return
    if ident == "su":
        m = SU_LINE.search(msg)
        if m:
            emit("notice", "priv_exec", via="su", invoker=m.group(2),
                 target_user=m.group(1))
        return
    if ident in ("pvedaemon", "pveproxy"):
        m = PVE_TASK.search(msg)
        if m:
            upid = m.group(2).split(":")
            emit("notice", "remote_task", service="pve", user=m.group(1),
                 task_type=upid[5] if len(upid) > 6 else "?",
                 task_id=upid[6] if len(upid) > 6 else "", upid=m.group(2))
            return
        m = PVE_AUTH_OK.search(msg)
        if m:
            emit("notice", "auth_success", service="pve", user=m.group(1))
            return
        m = PVE_AUTH_NO.search(msg)
        if m:
            emit("warning", "auth_failure", service="pve",
                 rhost=m.group(1), user=m.group(2))


def journal_watcher(stop: threading.Event) -> None:
    proc = subprocess.Popen(
        ["journalctl", "-f", "-n", "0", "-o", "json"],
        text=True, bufsize=1, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL)
    for line in proc.stdout:
        if stop.is_set():
            break
        try:
            classify_journal(json.loads(line))
        except (ValueError, KeyError):
            continue
    proc.terminate()


# ── Watcher 2: sessions / flows / tunnels poll ───────────────────────────────

def _session_ids() -> list:
    """Session ids via loginctl. `--json=short` (the working flag on
    systemd 260; `--output=json` is silently ignored) only exists on
    systemd >= 256 — on older hosts (e.g. Ubuntu 24.04 / systemd 255 it
    exits non-zero) fall back to parsing the legacy table, first column."""
    out = subprocess.run(["loginctl", "list-sessions", "--json=short"],
                         capture_output=True, text=True, timeout=10)
    if out.returncode == 0 and out.stdout.lstrip().startswith("["):
        return [str(r.get("session", "")) for r in json.loads(out.stdout)]
    out = subprocess.run(["loginctl", "list-sessions", "--no-legend",
                          "--no-pager"],
                         capture_output=True, text=True, timeout=10)
    return [ln.split()[0] for ln in out.stdout.splitlines() if ln.split()]


def _loginctl_sessions() -> dict:
    """session id → detail dict from loginctl."""
    try:
        sids = _session_ids()
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        emit("err", "watcher_degraded", watcher="loginctl", error=str(e))
        return {}
    result = {}
    for sid in sids:
        if not sid:
            continue
        try:
            show = subprocess.run(
                ["loginctl", "show-session", sid, "-p", "Remote", "-p",
                 "RemoteHost", "-p", "Service", "-p", "Type", "-p", "TTY",
                 "-p", "Name", "-p", "Class"],
                capture_output=True, text=True, timeout=10)
            kv = dict(ln.split("=", 1) for ln in show.stdout.splitlines()
                      if "=" in ln)
        except (OSError, subprocess.SubprocessError):
            kv = {}
        result[sid] = {"user": kv.get("Name", "?"),
                       "remote": kv.get("Remote", "no") == "yes",
                       "remote_host": kv.get("RemoteHost", ""),
                       "service": kv.get("Service", ""),
                       "type": kv.get("Type", ""), "tty": kv.get("TTY", ""),
                       "class": kv.get("Class", "")}
    return result


def _ss_tcp() -> list:
    try:
        out = subprocess.run(["ss", "-H", "-n", "-p", "-t", "-a"],
                             capture_output=True, text=True, timeout=10)
        return [ln for ln in out.stdout.splitlines() if ln.strip()]
    except (OSError, subprocess.SubprocessError):
        return []


def poll_watcher(stop: threading.Event, state: State) -> None:
    while not stop.is_set():
        # sessions
        sess = _loginctl_sessions()
        cur = set(sess)
        for sid in sorted(cur - state.sessions):
            d = sess[sid]
            lvl = "notice" if d["remote"] else "info"
            emit(lvl, "session_new", session=sid, baseline=state.first_run,
                 **d)
        for sid in sorted(state.sessions - cur):
            emit("info", "session_closed", session=sid)
        state.sessions = cur

        # flows + tunnel listeners
        listeners: set = set()
        tunnel_edges: set = set()
        for ln in _ss_tcp():
            t = ln.split()
            if len(t) < 5:
                continue
            st, local, peer = t[0], t[3], t[4]
            m = _USERS_RE.search(ln)
            comm = m.group(1) if m else ""
            try:
                lport = int(local.rsplit(":", 1)[1])
            except (IndexError, ValueError):
                continue
            if st == "LISTEN" and comm in ("sshd", "sshd-session", "ssh") \
                    and lport != 22:
                listeners.add(f"{comm}:{local}")
            elif st == "ESTAB":
                peer_ip = peer.rsplit(":", 1)[0]
                if lport == 22 and not peer.startswith(_LOOPBACK):
                    if state.fresh(f"in|{peer_ip}"):
                        emit("notice", "inbound_ssh_conn", rhost=peer_ip,
                             rport=peer.rsplit(":", 1)[1])
                elif comm == "ssh" and not peer.startswith(_LOOPBACK):
                    if state.fresh(f"out|{peer}"):
                        emit("info", "outbound_ssh_conn", dest=peer,
                             pid=int(m.group(2)) if m else None)
                elif peer.endswith(":7844"):
                    tunnel_edges.add(peer_ip)

        for lst in sorted(listeners - state.listeners):
            emit("warning", "tunnel_listener_new", listener=lst,
                 note="ssh port-forward endpoint appeared")
        for lst in sorted(state.listeners - listeners):
            emit("info", "tunnel_listener_gone", listener=lst)
        state.listeners = listeners

        edges = sorted(tunnel_edges)
        if edges != state.tunnel:
            emit("info", "tunnel_egress", service="cloudflared",
                 edges=edges, count=len(edges))
            state.tunnel = edges

        state.first_run = False
        stop.wait(POLL_S)


# ── Watcher 3: docker exec events ────────────────────────────────────────────

def docker_watcher(stop: threading.Event, state: State) -> None:
    try:
        proc = subprocess.Popen(
            ["docker", "events", "--format", "{{json .}}",
             "--filter", "type=container", "--filter", "event=exec_create"],
            text=True, bufsize=1, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL)
    except OSError as e:
        emit("info", "watcher_failed", watcher="docker", error=str(e))
        return
    for line in proc.stdout:
        if stop.is_set():
            break
        try:
            e = json.loads(line)
        except ValueError:
            continue
        attrs = e.get("Actor", {}).get("Attributes", {})
        action = e.get("Action", "")
        cmd = action.split(": ", 1)[1] if ": " in action else ""
        # recurring HEALTHCHECK execs collapse to one event/hour per
        # (container, command); novel exec commands emit immediately
        if state.fresh(f"dx|{attrs.get('name', '?')}|{cmd[:120]}"):
            emit("notice", "container_exec",
                 container=attrs.get("name", "?"),
                 image=attrs.get("image", "?"), command=cmd[:300])
    proc.terminate()


# ── Supervisor ───────────────────────────────────────────────────────────────

def _wrap(fn, name, stop, *args):
    fails = 0
    while not stop.is_set():
        started = time.time()
        try:
            fn(stop, *args)
        except Exception as e:  # noqa: BLE001 — watchers must not die silently
            emit("err", "watcher_failed", watcher=name, error=str(e))
        if stop.is_set():
            return
        fails = fails + 1 if time.time() - started < 60 else 1
        if fails >= 3:
            emit("err", "watcher_failed", watcher=name,
                 error="3 rapid failures — giving up (systemd will restart)")
            stop.set()
            return
        stop.wait(5)


def main() -> int:
    smoke = "--smoke" in sys.argv
    state = State()
    stop = threading.Event()
    emit("info", "daemon_start", first_run=state.first_run,
         known_flows=len(state.dedupe))

    signal.signal(signal.SIGTERM, lambda *_a: stop.set())
    signal.signal(signal.SIGINT, lambda *_a: stop.set())

    threads = [
        threading.Thread(target=_wrap, args=(journal_watcher, "journal", stop),
                         daemon=True),
        threading.Thread(target=_wrap,
                         args=(poll_watcher, "poll", stop, state), daemon=True),
        threading.Thread(target=_wrap,
                         args=(docker_watcher, "docker", stop, state),
                         daemon=True),
    ]
    for t in threads:
        t.start()

    deadline = time.time() + 25 if smoke else None
    while not stop.is_set():
        if deadline and time.time() > deadline:
            stop.set()
            break
        stop.wait(30)
        state.save()

    state.save()
    emit("info", "daemon_stop")
    return 0


if __name__ == "__main__":
    sys.exit(main())
