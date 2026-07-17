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
        ];
      };
    };
}
