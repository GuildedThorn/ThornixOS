{
  config,
  lib,
  pkgs,
  ...
}:

let
  dockerEnabled = config.virtualisation.docker.enable;

  # session-auditord — remote session & RCE auditor (observe-only,
  # 2026-08-04). Third audit layer beside rpc-auditor (poller) and
  # ipc-auditor (eBPF): watches the remote plane — SSH auth, logind
  # sessions w/ remote hosts, sudo/su privileged exec (Touchstone flows
  # included), PVE auth + remote tasks, ssh tunnel listeners, inbound/
  # outbound SSH flows, cloudflared egress, docker exec (container RCE).
  # Stream: journald identifier session-auditor → Loki inari-journal →
  # Grafana "Loki Inari Journal": {identifier="session-auditor"} | json
  sessionAuditord = pkgs.writeScriptBin "session-auditord" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./session-auditor/session-auditord.py}
  '';
in
{
  environment.systemPackages = [ sessionAuditord ]; # `session-auditord --smoke`

  systemd.services.session-auditor = {
    description = "Remote session & RCE auditor (observe-only)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ] ++ lib.optional dockerEnabled "docker.service";
    wants = lib.optional dockerEnabled "docker.service";
    path = [
      pkgs.iproute2
      pkgs.systemd
    ]
    ++ lib.optional dockerEnabled pkgs.docker;

    serviceConfig = {
      ExecStart = "${sessionAuditord}/bin/session-auditord${
        lib.optionalString (!dockerEnabled) " --no-docker"
      }";
      Restart = "on-failure";
      RestartSec = 15;
      SyslogIdentifier = "session-auditor";
      StateDirectory = "session-auditor"; # /var/lib/session-auditor/state.json

      # uid 0, bounding set trimmed to what the watchers need:
      #   CAP_SYS_PTRACE            — /proc peer enrichment
      #   CAP_DAC_READ_SEARCH       — full journal + /proc reads
      #   CAP_DAC_OVERRIDE          — /run/docker.sock (root:docker 660)
      CapabilityBoundingSet = [
        "CAP_SYS_PTRACE"
        "CAP_DAC_READ_SEARCH"
        "CAP_DAC_OVERRIDE"
      ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
    };
  };
}
