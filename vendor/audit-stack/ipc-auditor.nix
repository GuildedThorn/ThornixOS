{ pkgs, ... }:

let
  # ipc-auditord — kernel IPC auditor (eBPF, observe-only, 2026-08-04).
  # bpftrace sensor on security_socket_connect + inet_csk_accept feeds a
  # stdlib-Python supervisor that scopes (unix/netlink + loopback inet),
  # enriches, dedupes, and journals an audit stream (identifier
  # ipc-auditor). Event-driven companion to rpc-auditor.service — catches
  # the sub-poll-interval connections sampling cannot see. Same Grafana
  # path: "Loki Inari Journal", {identifier="ipc-auditor"} | json.
  ipcAuditord = pkgs.writeScriptBin "ipc-auditord" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./ipc-auditor/ipc-auditord.py}
  '';
in
{
  environment.etc."ipc-auditor/ipc-audit.bt".source = ./ipc-auditor/ipc-audit.bt;
  environment.systemPackages = [ ipcAuditord ];

  systemd.services.ipc-auditor = {
    description = "Kernel IPC auditor (eBPF, observe-only)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [
      pkgs.bpftrace
      pkgs.iproute2
    ];

    serviceConfig = {
      ExecStart = "${ipcAuditord}/bin/ipc-auditord";
      Restart = "on-failure";
      RestartSec = 15;
      SyslogIdentifier = "ipc-auditor";
      StateDirectory = "ipc-auditor"; # /var/lib/ipc-auditor/state.json
      LimitMEMLOCK = "infinity"; # BPF map/ringbuf pages

      # uid 0 with the bounding set trimmed to the sensor's needs:
      #   CAP_BPF + CAP_PERFMON     — load tracing progs, attach k(ret)probes
      #   CAP_SYSLOG                — kallsyms addresses for probe resolution
      #   CAP_SYS_PTRACE            — /proc/<pid>/{exe,cmdline,cgroup}
      #   CAP_DAC_READ_SEARCH/OVERRIDE — /proc + tracefs traversal
      CapabilityBoundingSet = [
        "CAP_BPF"
        "CAP_PERFMON"
        "CAP_SYSLOG"
        "CAP_SYS_PTRACE"
        "CAP_DAC_READ_SEARCH"
        "CAP_DAC_OVERRIDE"
      ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      # deliberately NOT set (bpftrace requirements):
      #   ProtectKernelTunables — would mount /sys read-only (tracefs writes)
      #   MemoryDenyWriteExecute — LLVM in-memory codegen in bpftrace
    };
  };
}
