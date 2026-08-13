#!/usr/bin/env python3
"""rpc-auditord — internal RPC surface auditor for mitonet hosts (observe-only).

Watches every Unix-domain socket and loopback TCP RPC connection on the
host, attributes both peers (pid/uid/exe/cmdline/container), and emits
structured JSON audit events. It never blocks or interferes — observe
mode, mirroring the nexus exec-guard precedent.

Canonical repo: ~/Code/Active/Current/rpc-auditor (the copy embedded in
nix-config services/rpc-auditor/ is the NixOS deployment of this file).

Platforms:
  linux    — `ss -p` + /proc three-tier attribution (fast path, inode-map
             fallback, per-netns tcp-table walk for container peers).
             Docker-cgroup processes are tagged with container short-id.
             Events go to stdout with sd-daemon `<N>` priority prefixes;
             run under systemd with SyslogIdentifier=rpc-auditor.
  freebsd  — `sockstat` collector (pfSense). Attribution comes directly
             from sockstat's USER/COMMAND/PID columns; exe paths resolved
             via `procstat -b` (cached), cmdlines via one `ps` sweep per
             cycle. No netns/containers. Events go to syslog(3) facility
             daemon, ident rpc-auditor — rides pfSense's existing remote
             syslog into the prod Alloy :5514 pipeline.

Grafana (tenant per host journal/syslog pipeline):
  {identifier="rpc-auditor"} | json

Events:
  daemon_start / daemon_stop
  rpc_connect         first sight (or re-sight after TTL) of a
                      (client exe, client uid, endpoint) pair —
                      level=warning while the pair is unknown to the
                      persisted baseline, info once known
  rpc_listener_new / rpc_listener_gone
  cycle_overflow      events dropped by the per-cycle cap (never silent)

Linux needs CAP_SYS_PTRACE + CAP_DAC_READ_SEARCH/CAP_DAC_OVERRIDE
(cross-uid and cross-netns /proc introspection) and iproute2 `ss` on
PATH. FreeBSD needs root (sockstat/procstat see all users' sockets).
Pure stdlib.
"""

import json
import os
import pwd
import re
import signal
import subprocess
import sys
import time

IS_FREEBSD     = sys.platform.startswith("freebsd")

INTERVAL_S     = 10          # poll cadence
RESEEN_TTL_S   = 6 * 3600    # re-log a known pair at most this often
SAVE_EVERY     = 30          # persist state every N cycles
MAX_EVENTS     = 120         # per-cycle emit cap (overflow is reported)
LEARN_CYCLES   = 60          # no prior state: first ~10 min = baseline
MAX_NETNS      = 64          # sanity cap on container-netns walks per cycle
STATE_FILE     = os.environ.get(
    "RPC_AUDITOR_STATE",
    "/var/db/rpc-auditor/state.json" if IS_FREEBSD
    else "/var/lib/rpc-auditor/state.json")

_USERS_RE  = re.compile(r'users:\(\("([^"]+)",pid=(\d+),fd=\d+\)')
_INO_RE    = re.compile(r"\bino:(\d+)")
_DOCKER_RE = re.compile(r"docker[-/]([0-9a-f]{12})[0-9a-f]*(?:\.scope)?")
_LOOPBACK  = ("127.", "[::1]", "::1")

_PRIO = {"info": "6", "notice": "5", "warning": "4", "err": "3"}

if IS_FREEBSD:
    import syslog
    syslog.openlog("rpc-auditor", 0, syslog.LOG_DAEMON)
    _SYSLOG_PRIO = {"info": syslog.LOG_INFO, "notice": syslog.LOG_NOTICE,
                    "warning": syslog.LOG_WARNING, "err": syslog.LOG_ERR}


def emit(level: str, event: str, **fields) -> None:
    doc = {"event": event, **fields}
    line = json.dumps(doc, sort_keys=True)
    if IS_FREEBSD:
        syslog.syslog(_SYSLOG_PRIO.get(level, syslog.LOG_INFO), line)
    sys.stdout.write(f"<{_PRIO.get(level, '6')}>{line}\n")
    sys.stdout.flush()


def _unknown() -> dict:
    return {"exe": "?", "pid": None, "uid": None, "user": "?", "cmd": ""}


# ═════════════════════════════════ Linux ═════════════════════════════════════

def _ss(*args: str) -> list:
    out = subprocess.run(["ss", "-H", "-n", "-p", *args],
                         capture_output=True, text=True, timeout=15)
    return [ln for ln in out.stdout.splitlines() if ln.strip()]


def socket_inode_map() -> dict:
    """socket inode → owning pid, from a full /proc/<pid>/fd sweep.
    Fallback for sockets `ss -p` failed to attribute. ~tens of ms as root."""
    m = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    tgt = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                if tgt.startswith("socket:["):
                    m.setdefault(tgt[8:-1], int(pid))
        except OSError:
            continue  # process exited mid-sweep
    return m


def proc_info(pid: int) -> dict:
    info = {"exe": "?", "pid": pid, "uid": None, "user": "?", "cmd": ""}
    try:
        info["exe"] = os.readlink(f"/proc/{pid}/exe")
    except OSError:
        try:  # kernel threads / raced exit — at least keep the comm name
            with open(f"/proc/{pid}/comm") as f:
                info["exe"] = f.read().strip()
        except OSError:
            pass
    try:
        with open(f"/proc/{pid}/status") as f:
            for ln in f:
                if ln.startswith("Uid:"):
                    info["uid"] = int(ln.split()[1])
                    break
        if info["uid"] is not None:
            try:
                info["user"] = pwd.getpwuid(info["uid"]).pw_name
            except KeyError:
                info["user"] = str(info["uid"])
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            info["cmd"] = f.read().replace(b"\0", b" ").decode(
                "utf-8", "replace").strip()[:200]
    except OSError:
        pass
    try:
        with open(f"/proc/{pid}/cgroup") as f:
            m = _DOCKER_RE.search(f.read())
        if m:
            info["container"] = m.group(1)
    except OSError:
        pass
    return info


def _attr(token: str, inode, inomap: dict) -> dict:
    """Attribute a socket: ss users token first, inode-map fallback second."""
    m = _USERS_RE.search(token or "")
    pid = int(m.group(2)) if m else (inomap.get(str(inode)) if inode else None)
    if pid is None:
        return _unknown()
    info = proc_info(pid)
    if info["exe"] == "?" and m:
        info["exe"] = m.group(1)
    return info


def unix_connections(inomap: dict) -> list:
    """[{endpoint, server, client}] for established unix-socket pairs.

    ss lists each connection twice (once per endpoint); rows pair up via
    local-inode ↔ peer-inode. The server side is the row whose local path
    is a real socket path (accepted sockets inherit the listener's path).
    """
    by_inode = {}
    for ln in _ss("-x", "-a"):
        t = ln.split()
        # netid state rq sq local_path local_inode peer_path peer_inode [users]
        if len(t) < 8 or t[1] != "ESTAB":
            continue
        by_inode[t[5]] = {"path": t[4], "inode": t[5], "peer_inode": t[7],
                          "users": t[8] if len(t) > 8 else ""}
    conns = []
    for row in by_inode.values():
        if row["path"] == "*":
            continue                       # client side — handled via server row
        peer = by_inode.get(row["peer_inode"])
        if peer is None:
            continue                       # unpaired (socketpair / raced)
        conns.append({"transport": "unix",
                      "endpoint": row["path"].rstrip("@"),  # abstract-name pad
                      "server": _attr(row["users"], row["inode"], inomap),
                      "client": _attr(peer["users"], peer["inode"], inomap)})
    return conns


def _hex_addr(hexip: str, hexport: str) -> str:
    """/proc/net/tcp{,6} hex address → the textual form ss prints."""
    port = int(hexport, 16)
    if len(hexip) == 8:                    # IPv4, little-endian
        b = bytes.fromhex(hexip)
        return f"{b[3]}.{b[2]}.{b[1]}.{b[0]}:{port}"
    if hexip == "00000000000000000000000001000000":
        return f"[::1]:{port}"
    return f"[v6:{hexip}]:{port}"


def netns_tcp_owners(inomap: dict) -> dict:
    """addr-string → pid for loopback ESTAB sockets living in NON-host
    network namespaces (container peers host-side sock_diag can't see)."""
    try:
        host_ns = os.stat("/proc/self/ns/net").st_ino
    except OSError:
        return {}
    reps = {}                              # netns inode → representative pid
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            ns = os.stat(f"/proc/{pid}/ns/net").st_ino
        except OSError:
            continue
        if ns != host_ns and ns not in reps:
            reps[ns] = int(pid)
            if len(reps) >= MAX_NETNS:
                break
    owners = {}
    for rep in reps.values():
        for tbl in ("tcp", "tcp6"):
            try:
                with open(f"/proc/{rep}/net/{tbl}") as f:
                    lines = f.readlines()[1:]
            except OSError:
                continue
            for ln in lines:
                t = ln.split()
                if len(t) < 10 or t[3] != "01":     # 01 = ESTABLISHED
                    continue
                ip, port = t[1].rsplit(":", 1)
                addr = _hex_addr(ip, port)
                if not addr.startswith(_LOOPBACK):
                    continue
                pid = inomap.get(t[9])
                if pid:
                    owners[addr] = pid
    return owners


def tcp_state(inomap: dict):
    """(loopback established connections, listening ports)."""
    listeners = set()
    rows = {}                              # local addr → (line, inode)
    estab = []
    for ln in _ss("-t", "-a", "-e"):
        t = ln.split()
        # state rq sq local peer …extended
        if len(t) < 5:
            continue
        state, local, peer = t[0], t[3], t[4]
        try:
            lport = int(local.rsplit(":", 1)[1])
        except (IndexError, ValueError):
            continue
        if state == "LISTEN":
            listeners.add(lport)
        elif state == "ESTAB" and local.startswith(_LOOPBACK) \
                and peer.startswith(_LOOPBACK):
            m = _INO_RE.search(ln)
            ino = m.group(1) if m else None
            rows[local] = (ln, ino)
            estab.append((local, lport, peer, ln, ino))
    conns = []
    ns_owners = None                       # lazy: only walk netns if needed
    for local, lport, peer, ln, ino in estab:
        if lport not in listeners:
            continue                       # this row is the client side
        server = _attr(ln, ino, inomap)
        peer_row = rows.get(peer)
        if peer_row is not None:
            client = _attr(peer_row[0], peer_row[1], inomap)
        else:                              # peer socket is in another netns
            if ns_owners is None:
                ns_owners = netns_tcp_owners(inomap)
            pid = ns_owners.get(peer)
            client = proc_info(pid) if pid else _unknown()
        conns.append({"transport": "tcp", "endpoint": f"tcp:{lport}",
                      "server": server, "client": client})
    return conns, listeners


def unix_listeners() -> set:
    out = set()
    for ln in _ss("-x", "-l"):
        t = ln.split()
        if len(t) >= 5 and t[4] != "*":
            out.add(t[4].rstrip("@"))
    return out


def linux_collect():
    """(connections, listener-endpoint set) via ss + /proc."""
    inomap = socket_inode_map()
    conns = unix_connections(inomap)
    tcp_conns, tcp_ports = tcp_state(inomap)
    conns += tcp_conns
    listeners = unix_listeners() | {f"tcp:{p}" for p in tcp_ports}
    return conns, listeners


# ═══════════════════════════════ FreeBSD ═════════════════════════════════════
# pfSense / stock FreeBSD. sockstat already prints USER COMMAND PID per
# socket, so attribution is column-parsing rather than /proc spelunking.
# procfs is not mounted by default — exe/cmdline come from procstat/ps.

_FBSD_EXE_CACHE = {}         # pid → exe path (procstat -b), reset never
                             # (pid reuse tolerated: exe only refines display)


def _sockstat(*args: str) -> list:
    out = subprocess.run(["sockstat", *args],
                         capture_output=True, text=True, timeout=15)
    lines = out.stdout.splitlines()
    return lines[1:] if lines else []      # drop USER COMMAND … header


def _fbsd_ps_cmds() -> dict:
    """pid → full cmdline, one ps sweep per cycle."""
    try:
        out = subprocess.run(["ps", "-ax", "-ww", "-o", "pid=,args="],
                             capture_output=True, text=True, timeout=15)
    except OSError:
        return {}
    cmds = {}
    for ln in out.stdout.splitlines():
        t = ln.strip().split(None, 1)
        if len(t) == 2 and t[0].isdigit():
            cmds[int(t[0])] = t[1][:200]
    return cmds


def _fbsd_exe(pid: int, comm: str) -> str:
    if pid in _FBSD_EXE_CACHE:
        return _FBSD_EXE_CACHE[pid]
    exe = comm
    try:
        out = subprocess.run(["procstat", "-b", str(pid)],
                             capture_output=True, text=True, timeout=5)
        for ln in out.stdout.splitlines()[1:]:
            t = ln.split()
            if t and t[0] == str(pid) and t[-1].startswith("/"):
                exe = t[-1]
                break
    except OSError:
        pass
    _FBSD_EXE_CACHE[pid] = exe
    return exe


def _fbsd_info(user: str, comm: str, pid_s: str, cmds: dict) -> dict:
    try:
        pid = int(pid_s)
    except ValueError:
        return _unknown()
    try:
        uid = pwd.getpwnam(user).pw_uid
    except KeyError:
        uid = None
    return {"exe": _fbsd_exe(pid, comm), "pid": pid, "uid": uid,
            "user": user, "cmd": cmds.get(pid, "")}


def freebsd_unix_state(cmds: dict):
    """(unix connections, unix listener paths) from sockstat -u.

    Row shape: USER COMMAND PID FD PROTO LOCAL [FOREIGN]
    Listeners bind a path in LOCAL; connected clients show the peer's
    bound path in FOREIGN (FreeBSD 13+ resolves unix peers). The pair key
    only needs the client side + endpoint path, so the missing kernel-side
    accepted-socket attribution is covered by the listener row.
    """
    listeners = {}                         # path → server info
    clients = []                           # (endpoint path, client info)
    for ln in _sockstat("-u"):
        t = ln.split()
        if len(t) < 6 or t[4] not in ("stream", "dgram", "seqpac"):
            continue
        local = t[5]
        foreign = t[6] if len(t) > 6 else ""
        if local.startswith("/"):
            listeners.setdefault(local, _fbsd_info(t[0], t[1], t[2], cmds))
        elif foreign.startswith("/"):
            clients.append((foreign, _fbsd_info(t[0], t[1], t[2], cmds)))
    conns = [{"transport": "unix", "endpoint": path,
              "server": listeners.get(path, _unknown()), "client": cl}
             for path, cl in clients]
    return conns, set(listeners)


def freebsd_tcp_state(cmds: dict):
    """(loopback tcp connections, listening ports) from sockstat -46."""
    listeners = set()
    srv_by_port = {}
    for ln in _sockstat("-46", "-l", "-P", "tcp"):
        t = ln.split()
        if len(t) < 6 or ":" not in t[5]:
            continue
        try:
            port = int(t[5].rsplit(":", 1)[1])
        except ValueError:
            continue
        listeners.add(port)
        srv_by_port.setdefault(port, _fbsd_info(t[0], t[1], t[2], cmds))
    rows = {}                              # local addr → info (for peer lookup)
    estab = []
    for ln in _sockstat("-46", "-c", "-P", "tcp"):
        t = ln.split()
        if len(t) < 7:
            continue
        local, foreign = t[5], t[6]
        if not (local.startswith(_LOOPBACK) and foreign.startswith(_LOOPBACK)):
            continue
        info = _fbsd_info(t[0], t[1], t[2], cmds)
        rows[local] = info
        estab.append((local, foreign, info))
    conns = []
    for local, foreign, info in estab:
        try:
            lport = int(local.rsplit(":", 1)[1])
        except ValueError:
            continue
        if lport not in listeners:
            continue                       # client side row
        client = rows.get(foreign, _unknown())
        conns.append({"transport": "tcp", "endpoint": f"tcp:{lport}",
                      "server": srv_by_port.get(lport, info), "client": client})
    return conns, listeners


def freebsd_collect():
    cmds = _fbsd_ps_cmds()
    conns, unix_l = freebsd_unix_state(cmds)
    tcp_conns, tcp_ports = freebsd_tcp_state(cmds)
    conns += tcp_conns
    listeners = unix_l | {f"tcp:{p}" for p in tcp_ports}
    return conns, listeners


collect = freebsd_collect if IS_FREEBSD else linux_collect


# ═══════════════════════════ State + main loop ═══════════════════════════════

def load_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"pairs": {}, "listeners": []}


def save_state(state: dict) -> None:
    tmp = STATE_FILE + ".tmp"
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, STATE_FILE)
    except OSError as e:
        emit("err", "state_save_failed", error=str(e))


def main() -> int:
    once = "--once" in sys.argv
    state = load_state()
    learning = not state["pairs"]          # no baseline yet → learn quietly
    known = state["pairs"]
    last_listeners = set(state.get("listeners", []))
    emit("info", "daemon_start", interval_s=INTERVAL_S,
         platform="freebsd" if IS_FREEBSD else "linux",
         known_pairs=len(known), learning=learning)

    stop = {"flag": False}

    def _sig(*_a):
        stop["flag"] = True

    signal.signal(signal.SIGTERM, _sig)
    signal.signal(signal.SIGINT, _sig)

    cycle = 0
    while not stop["flag"]:
        cycle += 1
        try:
            conns, listeners = collect()
        except Exception as e:  # noqa: BLE001 — one bad cycle must not kill us
            emit("err", "cycle_failed", error=str(e))
            time.sleep(INTERVAL_S)
            continue

        now = time.time()
        events = 0
        for c in conns:
            cl, sv = c["client"], c["server"]
            if cl["pid"] is not None and cl["pid"] == sv["pid"]:
                continue                   # self-connection
            key = f"{cl['exe']}|{cl['uid']}|{c['endpoint']}"
            fresh = key not in known
            if not fresh and now - known[key] < RESEEN_TTL_S:
                known[key] = now
                continue
            known[key] = now
            if events >= MAX_EVENTS:
                events += 1
                continue
            events += 1
            level = "info" if (not fresh or learning) else "warning"
            extra = {}
            if "container" in cl:
                extra["client_container"] = cl["container"]
            if "container" in sv:
                extra["server_container"] = sv["container"]
            emit(level, "rpc_connect", transport=c["transport"],
                 endpoint=c["endpoint"], baseline=learning and fresh,
                 new_pair=fresh and not learning,
                 client_exe=cl["exe"], client_pid=cl["pid"],
                 client_uid=cl["uid"], client_user=cl["user"],
                 client_cmd=cl["cmd"],
                 server_exe=sv["exe"], server_pid=sv["pid"], **extra)
        if events > MAX_EVENTS:
            emit("warning", "cycle_overflow", dropped=events - MAX_EVENTS)

        if last_listeners:
            for lst in sorted(listeners - last_listeners):
                emit("notice", "rpc_listener_new", endpoint=lst)
            for lst in sorted(last_listeners - listeners):
                emit("info", "rpc_listener_gone", endpoint=lst)
        last_listeners = listeners

        if cycle >= LEARN_CYCLES:
            learning = False
        if cycle % SAVE_EVERY == 0:
            save_state({"pairs": known, "listeners": sorted(listeners)})
        if once:
            break
        time.sleep(INTERVAL_S)

    save_state({"pairs": known, "listeners": sorted(last_listeners)})
    emit("info", "daemon_stop", cycles=cycle, known_pairs=len(known))
    return 0


if __name__ == "__main__":
    sys.exit(main())
