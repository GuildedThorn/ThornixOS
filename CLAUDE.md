# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Thorn's personal NixOS + Home Manager flake, covering ~10 hosts (workstation,
laptop, a public-facing website VM, lab/test VMs). See `README.md` for the
host list, GitOps deployment model, and the full sops secrets workflow —
don't duplicate that here, read it when a task touches deployment or secrets.

## Commands

```sh
nix flake check                                                            # evaluate + run flake checks
nix build ".#nixosConfigurations.<host>.config.system.build.toplevel"      # dry-build one host's closure (what CI does per host)
nixos-rebuild switch --flake .#<host>                                      # apply locally on that host (requires sudo, real system changes)
nixfmt-tree                                                                 # format all .nix files in the repo
nixfmt path/to/file.nix                                                    # format a single file
sops hosts/<host>/secrets.yaml                                             # edit that host's encrypted secrets
```

Host names: `firewall`, `mac`, `mitm`, `nixos`, `proxmox-guest`, `websites`,
`scout`, `soc`, `vmware-guest`, `vmware-test` (must match the CI matrix
in `.github/workflows/ci.yml` and the `flake.nixosConfigurations.<name>` set
in `modules/computers/`).

There's no local test suite — correctness is "does it evaluate and build."
`nix flake check` catches eval errors across all outputs; building a specific
host's toplevel catches package/module-level failures that check alone
sometimes misses. When editing a module used by multiple hosts, dry-build
each affected host, not just one.

## Architecture

flake-parts + [import-tree](https://github.com/vic/import-tree) (the
"dendritic" pattern): `flake.nix` declares only inputs; its `outputs` is
`import-tree ./modules`, which auto-imports every `.nix` file under
`modules/` as a flake-parts module. Nothing is wired up by file path — a
module contributes under a named option, and hosts assemble by referencing
those names. Adding a new module file is enough; nothing else needs to
import it explicitly.

Two option namespaces carry almost everything:

- `nixos.modules.<name>` (declared in `modules/core/nixos-modules.nix`) —
  NixOS-level module pieces. Named by area-prefix:
  `desktop-hyprland`, `processor-amd`, `graphics-intel`, `services-ssh`,
  `thorn-core`, `thorn-user`, etc. A host's `flake.nixosConfigurations.<host>`
  in `modules/computers/<host>.nix` is just a list of
  `config.nixos.modules.*` picks plus that host's `hosts/<host>/*.nix` data
  files (hardware-configuration, disko, networking, secrets) and an inline
  host-specific config block.
- `homeManager.modules.<name>` (declared in `modules/core/home-manager-modules.nix`)
  — Home Manager pieces, wired into NixOS via `nixos.modules.thorn-user`
  (`modules/users/thorn.nix`), which sets
  `home-manager.users.thorn = config.homeManager.modules.thorn`.

Individual home-manager feature modules (`modules/home-manager/*.nix`)
follow a consistent enable-flag convention:
`options.thorn.programs.<name>.enable` (or `thorn.desktop.<name>.enable` for
desktop/rice-type modules), gated with `config = lib.mkIf cfg.enable { ... }`.
Look at an existing module (e.g. `modules/home-manager/claude-code.nix` or
`modules/home-manager/firefox.nix`) as the template for a new one — declare
the option, then toggle it per-host in that host's `hosts/<host>/home.nix`.

`modules/core/thorn-core.nix` bundles the baseline every host imports
(`base`, `home-manager-base`, `thorn-user`) into `nixos.modules.thorn-core`;
every `modules/computers/<host>.nix` starts its module list with
`config.nixos.modules.thorn-core`.

### Directory map

```
flake.nix                  inputs only; outputs = import-tree ./modules
modules/
  computers/<host>.nix      one file per host: composes named modules + hosts/<host>/ files into flake.nixosConfigurations.<host>
  core/                      base config, the module-option plumbing (nixos.modules / homeManager.modules), thorn-core bundle
  desktop/  graphics/  processor/  services/  apps/  home-manager/  users/    named modules grouped by area
hosts/<host>/               per-host data: hardware-configuration, disko, networking, secrets.nix + secrets.yaml (sops), home.nix (which home-manager modules are enabled)
```

### Deployment model (GitOps via comin)

Each host runs `comin` tracking its own `deploy-<hostname>` branch, not
`main` (see `modules/users/thorn.nix`). CI (`.github/workflows/ci.yml`)
builds every host's toplevel from `main` in a matrix, and only fast-forwards
`deploy-<hostname>` once that specific host's build passes — so pushing to
`main` never deploys a config that hasn't been proven to evaluate and build
for that host. Keep this in mind when editing CI or the comin config: a
change that breaks one host's build blocks only that host's deploy branch,
not the others.
