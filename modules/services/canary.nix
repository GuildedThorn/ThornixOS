{
  # Detection canary: a scheduled, deliberately-distinctive process
  # execution whose ABSENCE from Loki is alertable.
  #
  # Why this exists. Everything else in the SOC stack assumes the detection
  # pipeline works; nothing tests it. That assumption failed in practice —
  # a LogQL filter matched the wrong thing and every audit panel silently
  # returned nothing for weeks, because an empty panel and a working-but-
  # quiet panel look identical. This closes that: it asserts the whole
  # chain end to end, auditd rule -> kernel audit -> journal -> Alloy ->
  # Loki -> the query itself. If any link breaks, the canary stops arriving
  # and the alert fires.
  #
  # The probe deliberately produces NO log output of its own. Writing a
  # marker to the journal would be the obvious way to make it easy to find,
  # and it would defeat the entire purpose: the line would arrive via
  # Alloy's ordinary journal shipping even with auditd completely broken,
  # so the alert would stay quiet exactly when the audit path had failed.
  # The only evidence this leaves is the execve record, which is precisely
  # the thing under test.
  #
  # Only meaningful on hosts running thorn.audit.execScope = "all". Under
  # the default "sessions" scope a systemd-timer process is invisible to
  # the rule — services run with loginuid unset — so the canary would never
  # be recorded and would alert forever. Desktops need no canary anyway:
  # they generate continuous real user exec activity, which is its own
  # liveness signal.
  nixos.modules.services-canary =
    { config, pkgs, ... }:
    let
      # The name IS the detection signal — it's what the alert greps for in
      # the EXECVE record's argv. Distinctive enough not to collide with
      # anything else on the system.
      probe = pkgs.writeShellScriptBin "siem-canary-probe" ''
        exit 0
      '';
    in
    {
      assertions = [
        {
          assertion = config.thorn.audit.execScope == "all";
          message = ''
            services-canary requires thorn.audit.execScope = "all".

            Under the default "sessions" scope the canary runs as a systemd
            service with loginuid unset, so the execve rule never records it
            and the canary alert would fire permanently — reporting a broken
            pipeline that is in fact fine.
          '';
        }
      ];

      systemd.services.siem-canary = {
        description = "SIEM detection canary probe";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${probe}/bin/siem-canary-probe";
        };
      };

      systemd.timers.siem-canary = {
        description = "SIEM detection canary schedule";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # Wait for the network and Alloy to settle after boot, then every
          # 10 minutes. The matching alert looks back 30 minutes, so two
          # consecutive misses are tolerated before it fires — enough that a
          # single slow scrape or a brief Loki blip doesn't page.
          OnBootSec = "5m";
          OnUnitActiveSec = "10m";
          AccuracySec = "1m";
          # Without this every host fires on the same second, which would
          # make the canary itself a small synchronised load spike.
          RandomizedDelaySec = "30s";
        };
      };
    };
}
