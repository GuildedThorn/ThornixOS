{
  # Fleet-wide Linux audit baseline (SOC Phase 2). Audit events reach the
  # journal via the kernel's audit multicast socket (_TRANSPORT=audit), so
  # the existing Alloy journal shipping in services-observability delivers
  # them to Loki on soc without extra plumbing.
  nixos.modules.services-audit =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.audit;
    in
    {
      options.thorn.audit.execScope = lib.mkOption {
        type = lib.types.enum [
          "sessions"
          "all"
        ];
        default = "sessions";
        description = ''
          Which execve calls to audit.

          "sessions" (default) records only processes carrying a loginuid
          (auid >= 1000) — a real user session. auid is set at login and
          inherited across setuid, so this still captures the whole post-sudo
          root shell while excluding the constant churn of systemd-spawned
          daemons, which on a desktop would dominate log volume.

          "all" drops that filter and records every execve, including daemons
          running under their own service accounts. Intended for headless
          hosts: with nobody logging in interactively, "sessions" records
          literally nothing there (measured — 100% of exec events on a
          workstation carry auid=1000, and system services run with auid
          unset), which leaves the one place a web-shell in a compromised
          service would run completely unwatched. Idle servers exec little,
          so the volume cost is modest; on a desktop it is not.
        '';
      };

      config = {
        # The priv-exec rules below watch /run/wrappers/bin/*, and a -w rule
        # on a path that doesn't exist yet fails the whole rule load. Both
        # audit-rules-nixos and suid-sgid-wrappers are pre-sysinit oneshots
        # with DefaultDependencies=false, and upstream orders neither against
        # the other — so whether the wrappers exist when the rules load is a
        # boot race (scout lost it consistently; the rest of the fleet
        # happened to win). Make the ordering explicit.
        systemd.services = {
          audit-rules-nixos = {
            after = [ "suid-sgid-wrappers.service" ];
            wants = [ "suid-sgid-wrappers.service" ];
          };

          # auditd deliberately refuses ordinary systemctl restarts. Teach
          # systemd its supported SIGHUP reload path and tie the unit hash to
          # the generated configuration so a NixOS switch actually applies
          # changed size/retention limits. Without this, auditd can continue
          # using its boot-time defaults indefinitely even though /etc shows
          # the new settings.
          auditd = {
            reloadIfChanged = true;
            restartTriggers = [ config.environment.etc."audit/auditd.conf".source ];
            serviceConfig.ExecReload = "${pkgs.audit}/bin/auditctl --signal reload";
          };
        };

        security.auditd = {
          enable = true;
          # Headless hosts audit every daemon exec and ship the same records
          # to Loki. Bound the redundant local copy so one unrotated audit.log
          # cannot consume the root filesystem (Sieve reached 2.6 GiB in two
          # days). Ten 100 MiB files retain a useful local incident window.
          settings = {
            max_log_file = lib.mkDefault 100;
            max_log_file_action = "ROTATE";
            num_logs = lib.mkDefault 10;
          };
        };
        security.audit = {
          enable = true;
          backlogLimit = 8192;
          rules = [
            # Account and privilege file changes
            "-w /etc/passwd -p wa -k identity"
            "-w /etc/group -p wa -k identity"
            "-w /etc/shadow -p wa -k identity"
            "-w /etc/sudoers -p wa -k privilege"

            # SSH server configuration
            "-w /etc/ssh -p wa -k sshd-config"

            # Kernel module loading/unloading
            "-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k modules"

            # System clock changes (log-forgery cover)
            "-a always,exit -F arch=b64 -S settimeofday,clock_settime -k time-change"

            # Privilege escalation through the setuid wrappers
            "-w /run/wrappers/bin/sudo -p x -k priv-exec"
            "-w /run/wrappers/bin/su -p x -k priv-exec"
          ]
          # Process execution — without this the fleet has no answer to "what
          # actually ran on this box", since every other rule here watches
          # state changes rather than behaviour.
          #
          # Both arches in either mode: the 32-bit syscall table is rarely
          # used on x86_64, which is exactly why it is worth watching as an
          # evasion path.
          #
          # auid is spelled numerically (4294967295 == unset) rather than as
          # `-1` or `unset`: those are auditctl parser conveniences, and a
          # rule this file gets wrong fails the audit-rules unit on every host
          # in the fleet at once. The literal is the portable form.
          ++ (
            if cfg.execScope == "all" then
              [
                "-a always,exit -F arch=b64 -S execve -k exec"
                "-a always,exit -F arch=b32 -S execve -k exec"
              ]
            else
              [
                "-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k exec"
                "-a always,exit -F arch=b32 -S execve -F auid>=1000 -F auid!=4294967295 -k exec"
              ]
          );
        };
      };
    };
}
