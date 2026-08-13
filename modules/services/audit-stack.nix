{ inputs, ... }:
{
  nixos.modules.services-audit-stack = {
    # audit-stack does not have an upstream flake interface yet, so consume
    # the three source modules directly from its locked non-flake input.
    imports = [
      "${inputs.audit-stack}/rpc-auditor.nix"
      "${inputs.audit-stack}/ipc-auditor.nix"
      "${inputs.audit-stack}/session-auditor.nix"
    ];
  };
}
