{ pkgs, ... }:

let
  # rpc-auditord — observe-only internal RPC surface auditor (2026-08-04).
  # Watches all Unix-domain sockets + loopback TCP RPC on the host,
  # attributes both peers, and emits structured JSON events to journald
  # (identifier rpc-auditor). The full-journal Alloy pipeline ships them
  # to prod Loki tenant inari-journal → Grafana "Loki Inari Journal":
  #   {identifier="rpc-auditor"} | json
  # Observe mode only — it never blocks anything.
  rpcAuditord = pkgs.writeScriptBin "rpc-auditord" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./rpc-auditor/rpc-auditord.py}
  '';
in
{
  environment.systemPackages = [ rpcAuditord ]; # `rpc-auditord --once` for ad-hoc audits

  systemd.services.rpc-auditor = {
    description = "Internal RPC surface auditor (observe-only)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.iproute2 ]; # `ss` — sock_diag with peer + process attribution

    serviceConfig = {
      ExecStart = "${rpcAuditord}/bin/rpc-auditord";
      Restart = "on-failure";
      RestartSec = 10;
      SyslogIdentifier = "rpc-auditor";
      StateDirectory = "rpc-auditor"; # /var/lib/rpc-auditor/state.json

      # Runs as uid 0 for universal /proc traversal, but the capability
      # bounding set is trimmed to exactly what attribution needs:
      #   CAP_SYS_PTRACE      — /proc/<pid>/{fd,exe,ns} of foreign procs
      #   CAP_DAC_READ_SEARCH — read-only DAC bypass for /proc walks
      #   CAP_DAC_OVERRIDE    — cross-netns /proc/<pid>/net tables
      # Everything else root could normally do (net admin, module load,
      # mknod, chown, kill, …) is out of the bounding set.
      CapabilityBoundingSet = [
        "CAP_SYS_PTRACE"
        "CAP_DAC_READ_SEARCH"
        "CAP_DAC_OVERRIDE"
      ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true; # socket topology comes from netlink, not /tmp paths
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
    };
  };
}
