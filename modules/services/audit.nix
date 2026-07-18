{
  # Fleet-wide Linux audit baseline (SOC Phase 2). Audit events reach the
  # journal via the kernel's audit multicast socket (_TRANSPORT=audit), so
  # the existing Alloy journal shipping in services-observability delivers
  # them to Loki on soc without extra plumbing.
  nixos.modules.services-audit =
    { ... }:
    {
      security.auditd.enable = true;
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

          # Process execution. Without this the fleet has no answer to "what
          # actually ran on this box" — the single biggest hole in the
          # endpoint telemetry, since every other rule here watches state
          # changes rather than behaviour.
          #
          # Scoped to loginuid-carrying processes (auid >= 1000, i.e. a real
          # user session) rather than everything. auid is set at login and
          # inherited across setuid, so this still captures the whole
          # post-sudo root shell — the usual hands-on-keyboard attack path —
          # while excluding the constant churn of systemd-spawned daemons,
          # which on NixOS would otherwise dominate the log volume.
          #
          # DELIBERATE GAP: code executed by a daemon running under its own
          # service account (auid unset) is NOT captured. A web-shell in a
          # compromised service is therefore invisible to this rule; Suricata
          # and CrowdSec are what cover that path today. Widening to
          # unfiltered execve is a volume decision, not a config one.
          #
          # auid is spelled numerically (4294967295 == unset) rather than as
          # `-1` or `unset`: those are auditctl parser conveniences, and a
          # rule this file gets wrong fails the audit-rules unit on every
          # host in the fleet at once. The literal is the portable form.
          "-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k exec"
          # 32-bit syscall table too — rarely used on x86_64, which is
          # exactly why it's worth watching as an evasion path.
          "-a always,exit -F arch=b32 -S execve -F auid>=1000 -F auid!=4294967295 -k exec"
        ];
      };
    };
}
