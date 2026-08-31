# ThornixOS

Personal NixOS and Home Manager fleet configuration built with flake-parts and
import-tree. It manages workstations, laptops, network infrastructure, lab
systems, and an internal service platform through one declarative inventory.

## Highlights

- Dendritic module layout with named NixOS and Home Manager modules
- GitOps deployment through comin and a gated `production` branch
- Hydra builds, Cachix publication, and fast-forward-only promotion
- Declarative Proxmox VM profiles and guarded one-shot provisioning
- SOPS-encrypted host secrets with SSH-derived age recipients
- Centralized Prometheus, Loki, Grafana, Alloy, audit, and SIEM coverage
- Reproducible backup contracts with freshness and restore-test monitoring
- CI-enforced formatting, Statix analysis, dead-code checks, and fleet evaluation

## Documentation

Full operational documentation lives in the
[GitHub Wiki](https://github.com/GuildedThorn/ThornixOS/wiki).

| Topic | Documentation |
|---|---|
| Fleet design and host inventory | [Architecture and hosts](https://github.com/GuildedThorn/ThornixOS/wiki/Architecture-and-Hosts) |
| GitOps and VM provisioning | [Deployment](https://github.com/GuildedThorn/ThornixOS/wiki/Deployment) |
| Monitoring, logging, and SIEM | [Observability](https://github.com/GuildedThorn/ThornixOS/wiki/Observability) |
| Encrypted secret operations | [Secrets](https://github.com/GuildedThorn/ThornixOS/wiki/Secrets) |
| GitHub Actions and Hydra | [CI](https://github.com/GuildedThorn/ThornixOS/wiki/CI) |
| Internal service runbooks | [Wiki home](https://github.com/GuildedThorn/ThornixOS/wiki#internal-services) |

## Repository Layout

```text
flake.nix                  flake inputs; outputs import modules automatically
modules/computers/         host composition and nixosConfigurations
modules/core/              baseline config and module plumbing
modules/services/          reusable service modules
modules/home-manager/      user programs and desktop features
hosts/<host>/              host networking, disks, secrets, and service data
hosts/inventory.nix        authoritative fleet and monitoring membership
hosts/backup-catalog.nix   recovery contracts and freshness policy
```

## Common Commands

```sh
# Evaluate flake outputs and checks
nix flake check

# Dry-build one host
nix build ".#nixosConfigurations.<host>.config.system.build.toplevel"

# Apply locally on that host
sudo nixos-rebuild switch --flake .#<host>

# Bootstrap from promoted production configuration
sudo nixos-rebuild switch \
  --flake github:GuildedThorn/ThornixOS/production#<host>
```

`main` is never deployed directly. Forge builds every production host, confirms
closures in Cachix, then fast-forwards `production`; comin activates that proven
revision on each host.
