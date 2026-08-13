{ ... }:
{
  nixos.modules.services-audit-stack = {
    # Keep the unpublished audit-stack snapshot inside ThornixOS so builds
    # do not depend on a GitHub revision the maintainer cannot push.
    imports = [
      ../../vendor/audit-stack/rpc-auditor.nix
      ../../vendor/audit-stack/ipc-auditor.nix
      ../../vendor/audit-stack/session-auditor.nix
    ];
  };
}
