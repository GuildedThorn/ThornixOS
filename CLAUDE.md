# Working on ThornixOS

Read [README.md](README.md) for the repository map and deployment model, and
[docs/maintenance.md](docs/maintenance.md) for module conventions and validation.
Keep those documents authoritative rather than duplicating instructions here.

- `hosts/inventory.nix` defines fleet membership and host platforms. Query
  `.#thornixFleet` when tooling needs the fleet; do not maintain a second list.
- Every Nix file under `modules/` is imported as a flake-parts module. Ordinary
  NixOS modules belong under `hosts/` or inside a named deferred module.
- Keep `modules/computers/<host>.nix` focused on composition. Machine settings
  belong under `hosts/<host>/`; shared features belong in named modules.
- Preserve state versions, provisioning readiness checks, compatibility pins,
  encrypted secrets, and the gated `production` promotion contract.
- Use `nix fmt`, the source and Compose lifecycle checks, and `bash scripts/check-fleet` during
  maintenance. Build affected system closures before production promotion.
- Evaluation and builds do not authorize activation. `nixos-rebuild switch`
  changes a running machine.
