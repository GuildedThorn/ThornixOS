# ThornixOS

my nix config, dont mind the name, a friend thought it was funny

## Layout

The flake is [flake-parts](https://github.com/hercules-ci/flake-parts) +
[import-tree](https://github.com/vic/import-tree) (the "dendritic" pattern):
`flake.nix` holds only inputs, and every `.nix` file under `modules/` is
auto-imported as a flake-parts module. Nothing is wired up by path — each file
contributes named pieces (`nixos.modules.<name>`) or whole hosts
(`flake.nixosConfigurations.<name>`), and hosts compose from those names.

```
flake.nix                  inputs only; outputs = import-tree ./modules
modules/
  computers/<host>.nix     one file per host: composes named modules + hosts/<host>/ files
  core/                    base config, thorn-core bundle, module plumbing
  desktop/  graphics/  processor/  services/  home-manager/  users/
hosts/<host>/              per-host data: hardware-configuration, disko,
                           networking, secrets.nix + secrets.yaml (sops)
```

## Hosts

| Host | What it is |
|---|---|
| `nixos` | Main workstation — AMD, Hyprland, home-manager, the works |
| `websites` | Proxmox VM serving [guildedthorn.com](https://guildedthorn.com) — see below |
| `mac` | Intel/AMD-graphics machine, Hyprland desktop |
| `scout` | Intel laptop, Hyprland desktop |
| `firewall` | Firewall box |
| `mitm` / `proxmox-mitm` | MITM lab machines (bare metal / Proxmox VM) |
| `proxmox-guest` | General Proxmox VM, XFCE+i3 |
| `vmware-guest` / `vmware-test` | VMware VMs, XFCE+i3 |

Bootstrap a host once by hand; after that comin owns it (next section):

```sh
nixos-rebuild switch --flake github:GuildedThorn/ThornixOS#<host>
```

## Deployment (GitOps via comin)

Every host runs [comin](https://github.com/nlewo/comin) watching this repo's
`main` branch. Push to `main` and each machine pulls, builds its own
`nixosConfigurations.<hostname>`, and switches — no push-based deploys, no SSH
from CI. Activation is diff-based: a commit that doesn't change a host's
closure is a no-op for it, and a failed build leaves the old generation
running.

## guildedthorn.com

The website (ASP.NET Core + React) lives in its own repo,
[GuildedThorn.com](https://github.com/GuildedThorn/GuildedThorn.com), and
enters this flake as the `guildedthorn-com` input, which also provides the
NixOS module (`services.guildedthorn`). The `websites` VM fronts the app with
a Cloudflare Tunnel (outbound-only; nothing but SSH is exposed), plus Owncast
for the live stream and RabbitMQ for the guestbook publisher.

Deploying a new site version is a lock bump:

```sh
nix flake update guildedthorn-com
git commit flake.lock -m "chore: bump guildedthorn-com"
git push   # comin on the VM picks it up within ~a minute
```

Only `guildedthorn.service` restarts (a few seconds); other services on the
VM are untouched.

## SOC / observability

The `soc` VM (172.16.25.51) is the fleet's monitoring and SIEM hub. Nothing
about it is push-based — every host ships to it, and it pulls metrics back.

**What runs where:**

- **soc**: Loki (logs, chunks in the NAS's SeaweedFS S3 `loki` bucket, 90d
  retention), Prometheus (metrics, 90d local), and Grafana
  (`http://soc.guildedthorn.arpa:3000`).
- **every host** (via `services-observability` + `services-audit`, both in
  `thorn-core`): Grafana Alloy tails the systemd journal and pushes it to
  Loki; `node_exporter` exposes metrics on :9100 for Prometheus to scrape;
  auditd adds a baseline of security rules (identity/sudoers/sshd changes,
  module loads, privilege exec) whose events ride the same journal stream.
- **websites**: additionally runs Suricata (af-packet IDS on `lo`+`eth0` —
  `lo` because real ingress is the Cloudflare tunnel, readable only on
  loopback) and CrowdSec (detect-only, no bouncer). Suricata's EVE JSON
  ships to Loki via a second Alloy file source.

**How a log becomes a graph:** journal line → Alloy (`loki.source.journal`)
→ Loki on soc → Grafana panel / alert rule. Metrics are the reverse pull:
Prometheus on soc scrapes each host's `:9100`. Both directions depend on
`<host>.guildedthorn.arpa` resolving — static hosts are pinned in
`modules/core/lan-hosts.nix`; DHCP hosts (the laptops) need a pfSense static
reservation or their Prometheus target shows down.

**Dashboards & alerts** are provisioned from the repo, so they survive
rebuilds and aren't hand-clicked:

- Dashboards: `hosts/soc/dashboards/*.json` (SOC Overview, Fleet Health),
  wired in via `services.grafana.provision.dashboards`.
- Alert rules: inline in `modules/computers/soc.nix` under
  `provision.alerting` (host down, unit failed, SSH brute force, Suricata
  alert, CrowdSec scenario, Loki down, log-ingest stalled). Dashboard-only
  for now — no contact points until a notification channel is chosen.

**Adding a new detection** is usually two edits: a Loki/Prometheus query as
a new dashboard panel, and a matching entry in the `alerting` rules list
(copy an existing `(rule { … })` block — they share a helper that builds the
Grafana instant-query + threshold shape). If it needs a new data source
(e.g. a new sensor's logs), add an Alloy file source on the emitting host
the way `services-suricata` does.

## CI

GitHub Actions runs `nix flake check` and dry-run-builds every host's
toplevel on each push/PR (`.github/workflows/ci.yml`).

## Secrets (sops)

Secrets are encrypted with [sops](https://github.com/getsops/sops) /
[sops-nix](https://github.com/Mic92/sops-nix) and committed to the repo as
ciphertext. Recipients are declared per-file in `.sops.yaml`:

- **My GPG key** (YubiKey-backed) — lets me edit any secrets file from my
  workstation. Decrypting/re-encrypting prompts for the YubiKey PIN.
- **Each host's own age key**, derived from its SSH host key
  (`/etc/ssh/ssh_host_ed25519_key`) via `ssh-to-age`. Lets `sops-nix` decrypt
  unattended during system activation — no YubiKey needed on the host.

`sops` and `ssh-to-age` are in every host's system packages
(`modules/core/base.nix`). If you're on a machine that hasn't been rebuilt
yet, use `nix shell nixpkgs#sops nixpkgs#ssh-to-age` instead.

### Editing an existing secrets file

```sh
sops hosts/<host>/secrets.yaml
```

Opens `$EDITOR` on the decrypted contents; saving re-encrypts to all
recipients configured for that path in `.sops.yaml`.

### Adding a new secret to a host that already has one

1. `sops hosts/<host>/secrets.yaml` and add the key.
2. Declare it in `hosts/<host>/secrets.nix`:
   ```nix
   sops.secrets.my_new_secret = { };
   ```
3. Rebuild. It shows up at `/run/secrets/my_new_secret`, owned by root:root
   0400 by default — use `sops.secrets.<name>.owner`, `.group`, `.mode`, or
   `.path` to change that, and reference it elsewhere in config via
   `config.sops.secrets.<name>.path`.

### Setting up secrets on a new host

1. Get the host's SSH host public key (from `/etc/ssh/ssh_host_ed25519_key.pub`
   after first boot, or `ssh-keyscan -t ed25519 <host>` over the network),
   then convert it:
   ```sh
   ssh-to-age -i ssh_host_ed25519_key.pub
   ```
2. Add the resulting `age1...` key to `.sops.yaml` under `keys:`, and add a
   `creation_rules:` entry for `hosts/<host>/secrets\.ya?ml$` listing my `pgp`
   fingerprint and that host's `age` key.
3. Create the encrypted file (plaintext YAML first, then encrypt in place):
   ```sh
   sops --encrypt --in-place hosts/<host>/secrets.yaml
   ```
4. Create `hosts/<host>/secrets.nix` with `sops.defaultSopsFile = ./secrets.yaml;`
   and `sops.secrets.<name> = { };` entries, then add it to that host's module
   list (see `modules/computers/websites.nix` for the pattern).

### Rotating recipients

After changing `.sops.yaml` (adding/removing a key), re-encrypt affected
files to match:

```sh
sops updatekeys hosts/<host>/secrets.yaml
```

### Recovering after an OS reinstall / host key loss

A wipe generates a brand-new `/etc/ssh/ssh_host_ed25519_key`, so the host's
old age key is gone and it can no longer decrypt its `secrets.yaml`. This
never locks *me* out, though — my GPG key is always a co-recipient, so I can
decrypt from my workstation the whole time. Fix the host's unattended path
once it's back up:

1. Reinstall the host as usual (host key regenerates on first boot).
2. Get the new host age key and swap it into `.sops.yaml`:
   ```sh
   ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
   ```
   Replace the old `age1...` value for that host under `keys:` in `.sops.yaml`.
3. Re-encrypt for the new recipient (run from a machine with my GPG key/YubiKey):
   ```sh
   sops updatekeys hosts/<host>/secrets.yaml
   ```
4. Rebuild the host — `sops-nix` can now decrypt again.

Host private keys are never backed up on purpose — losing one just means a
`updatekeys` round-trip, not a lost secret.
