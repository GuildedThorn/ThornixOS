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
| `identity` | Proxmox VM running Authentik and PostgreSQL for internal SSO/MFA |
| `pixie` | Proxmox VM providing a locked ThornixOS rescue image plus iPXE/netboot.xyz |
| `atlas` | Proxmox VM running NetBox as the infrastructure inventory/IPAM source of truth |
| `anvil` | Proxmox VM running the online ThornCloud issuing CA and internal ACME endpoint |
| `sieve` | Proxmox VM running Greenbone vulnerability management and active assessment |
| `hound` | Proxmox VM running Velociraptor endpoint visibility and forensic response |
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

### One-shot VM installs from `mac`

Once CI has promoted `deploy-mac` and the new VM's deploy branch, open an
agent-forwarded session to the hypervisor and run the mac-only provisioner:

```sh
ssh -A root@172.16.25.3
thornix-provision identity
# or
thornix-provision pixie
# or
thornix-provision atlas
# or
thornix-provision anvil
# or
thornix-provision sieve
# or
thornix-provision hound
```

The currently declared profiles are soc (VM 103, `172.16.25.51`, 60 GiB),
identity (VM 104, `172.16.25.52`, 40 GiB), pixie (VM 105,
`172.16.25.53`, 20 GiB), atlas (VM 106, `172.16.25.54`, 40 GiB), anvil
(VM 107, `172.16.25.55`, 20 GiB), sieve (VM 108, `172.16.25.56`, 60 GiB),
and hound (VM 109, `172.16.25.57`, 80 GiB).
The utility prebuilds the promoted closure,
boots a key-only static-IP installer, verifies the Proxmox ownership marker,
NIC MAC, ISO label, disk serial and disk size, and then runs Disko plus
`nixos-anywhere`. Type `<profile>/<vmid>` at its destructive confirmation. If
an install is interrupted, inspect the VM and resume it explicitly with
`thornix-provision <profile> --resume`; the utility never deletes a VM, and a
post-install resume cannot run Disko again.

Profiles are data-driven. Any `hosts/<name>/proxmox.nix` file is discovered
automatically when `mac` evaluates; it declares the VMID, static address,
resources, disk serial, admin keys, and optional readiness probes. The
provisioner validates that VMIDs, addresses, and disk serials are unique and
generates the installer and `thornix-provision <name>` entry without a shell
code change. The host must also expose `nixosConfigurations.<name>` with a
Disko script targeting `/dev/sda`; the default deploy source is
`deploy-<name>#<name>`.

### Pixie network boot

Pixie serves only TFTP bootstrap firmware on UDP 69 and immutable HTTP boot
assets on TCP 80. It never runs DHCP or DNS: pfSense remains authoritative.
The embedded BIOS (`undionly.kpxe`) and x86_64 UEFI (`ipxe.efi`, with
`snp.efi` as a firmware-compatibility alternative) loaders chain to
`http://172.16.25.53/boot.ipxe`. The menu defaults back to the local disk after
ten seconds and provides:

- a local, reproducible ThornixOS rescue/NixOS installer built from this
  flake's locked nixpkgs, with key-only root SSH access;
- the upstream netboot.xyz menu for additional installers and diagnostics;
- an iPXE shell and firmware reboot/local-boot actions.

Add a pfSense DNS override for `pixie.guildedthorn.arpa` at `172.16.25.53`.
On each pfSense DHCP interface where PXE should work, set the next-server/TFTP
server to `172.16.25.53` and choose the boot filename by client architecture:
`undionly.kpxe` for legacy BIOS or `ipxe.efi` for x86_64 UEFI. Do not enable a
second DHCP server. TFTP and HTTP are firewall-limited to `192.168.1.0/24` and
`172.16.25.0/24`; they are bootstrap protocols, not authenticated transport,
so enable network boot only for trusted clients. These locally-built iPXE
executables are not Secure Boot signed; disable Secure Boot on a client before
using them. The local ThornixOS target is flake-locked, while choosing
netboot.xyz intentionally trusts that upstream service and requires Internet
access.

### Atlas infrastructure inventory

Atlas runs NetBox behind nginx at `https://atlas.guildedthorn.arpa/`.
PostgreSQL, Redis, and the NetBox application communicate through local Unix
sockets; no database password is exposed on the network. NetBox's secret key
and API pepper are generated into persistent service state on first boot.

nginx serves a ThornCloud_CA certificate for `atlas.guildedthorn.arpa`; its
private key is decrypted from SOPS directly to a `0400` nginx-owned runtime
file. Add a pfSense DNS override for `atlas.guildedthorn.arpa` at
`172.16.25.54`, then create the first account if one does not already exist:

```sh
ssh -t root@172.16.25.54 netbox-manage createsuperuser
```

Atlas's SSH host-key age recipient permits unattended SOPS decryption. The SOC
scrapes its node, comin, and native NetBox application metrics; Alloy ships its
journal and audit records to Loki, including the end-to-end detection canary.
Authentik OIDC remains an optional follow-up enrollment step.

### Anvil internal certificate authority

Anvil runs `step-ca` at `https://anvil.guildedthorn.arpa/` and publishes the
ACME directory at
`https://anvil.guildedthorn.arpa/acme/thorncloud/directory`. The ThornCloud
root private key is deliberately offline and must never be copied to Anvil or
put in SOPS. Anvil receives only an encrypted, pathLen=0 issuing intermediate;
its ACME provisioner issues only `*.guildedthorn.arpa` hostnames, rejects
literal wildcard and IP certificates, and defaults to 24-hour certificates
with a seven-day maximum.

Onboarding is intentionally two-stage because the final SOPS recipient is
derived from the installed VM's real SSH host key:

1. Commit and push the bootstrap configuration, wait for `deploy-mac` and
   `deploy-anvil`, then run `thornix-provision anvil` from an agent-forwarded
   root session on mac. The first closure contains no CA private material and
   leaves `step-ca` disabled.
2. From the workstation, capture the installed ed25519 host key. Compare the
   `ssh-keygen` SHA256 fingerprint with the pinned fingerprint printed by
   `thornix-provision` before accepting the age recipient:

   ```sh
   anvil_host_key=$(mktemp)
   ssh-keyscan -t ed25519 172.16.25.55 > "$anvil_host_key"
   ssh-keygen -lf "$anvil_host_key"
   ssh-to-age < "$anvil_host_key"
   ```

3. Add that age value as `&host_anvil` in `.sops.yaml`, add it to the shared
   telemetry rule, and add a `hosts/anvil/secrets.yaml` creation rule. Then
   rewrap the existing fleet writer identity:

   ```sh
   sops updatekeys hosts/shared/telemetry-secrets.yaml
   ```

4. On the machine where the offline root key is available, create the
   encrypted EC P-256 issuing key and public five-year intermediate. Replace
   only the `/path/to/offline/ThornCloud_CA.key` placeholder; an encrypted root
   key prompts for its own password interactively.

   ```sh
   umask 077
   anvil_work=$(mktemp -d)
   nix shell .#nixosConfigurations.anvil.pkgs.openssl -c \
     openssl rand -base64 48 > "$anvil_work/intermediate.pass"
   nix shell .#nixosConfigurations.anvil.pkgs.step-cli -c \
     step certificate create "ThornCloud Anvil Intermediate CA" \
       certs/anvil-intermediate.crt "$anvil_work/intermediate.key" \
       --profile intermediate-ca \
       --ca certs/ThornCloud_CA.crt \
       --ca-key /path/to/offline/ThornCloud_CA.key \
       --password-file "$anvil_work/intermediate.pass" \
       --kty EC --curve P-256 --not-after 43800h
   ```

5. Run `sops hosts/anvil/secrets.yaml` and add the encrypted private-key PEM
   and its generated password under these exact keys:

   ```yaml
   step_ca_intermediate_key: |-
     -----BEGIN ENCRYPTED PRIVATE KEY-----
     ...
     -----END ENCRYPTED PRIVATE KEY-----
   step_ca_intermediate_password: "..."
   ```

   Commit only `.sops.yaml`, the rewrapped shared telemetry file, the SOPS
   ciphertext, and the public intermediate certificate. Delete the temporary
   plaintext password and encrypted-key working copy after confirming SOPS can
   decrypt it. CI verifies the chain, expiry, and pathLen before promoting
   `deploy-anvil`; comin then activates `step-ca` on the bootstrap VM.

Add a pfSense DNS override for `anvil.guildedthorn.arpa` at `172.16.25.55`.
Only the trusted internal subnets can reach SSH or the CA, while node/comin
metrics remain source-limited to SOC. Confirm activation with:

```sh
curl --cacert certs/ThornCloud_CA.crt \
  https://anvil.guildedthorn.arpa/health
curl --cacert certs/ThornCloud_CA.crt \
  https://anvil.guildedthorn.arpa/acme/thorncloud/directory
```

### Sieve vulnerability management

Sieve runs Greenbone Community Edition at
`https://sieve.guildedthorn.arpa/`. NixOS nginx is the only network-facing
listener and obtains its certificate from Anvil. Greenbone's own generated
TLS listener is published only on loopback. Executable container images are
pinned to reviewed linux/amd64 manifests; a daily timer refreshes only the
rolling Community Feed data images.

Push the configuration and wait for both `deploy-mac` and `deploy-sieve`, add
a pfSense host override for `sieve.guildedthorn.arpa` at `172.16.25.56`, then
provision from the hypervisor:

```sh
ssh -A root@172.16.25.3
thornix-provision sieve
```

The first boot may spend tens of minutes downloading images and importing the
initial feed, so Sieve's profile has a one-hour readiness window. The upstream
`admin/admin` credential is replaced before the UI can answer remotely. Read
the generated bootstrap credential and change it after the first login:

```sh
ssh root@172.16.25.56 sieve-admin-password
```

Deployment does not start an active scan. The explicitly authorized owner-run
scope is available with `sieve-authorized-scope`; create targets and schedules
in GSA only after reviewing it. OPT1 targets are directly reachable. To assess
the LAN, add an explicit pfSense OPT1 pass rule from Sieve (`172.16.25.56`) to
the LAN net (`192.168.1.0/24`); do not add a WAN inbound rule or authorize
public ranges as scan targets. Container status and manual feed refreshes are
available through `sieve-compose ps` and `sieve-update-feeds`.

Sieve telemetry is encrypted to its SSH-derived age recipient. The dedicated
`hosts/sieve/telemetry.nix` enrollment marker enables Alloy, the detection
canary, SOC node and comin targets, the HTTPS blackbox probe, and log-silence
monitoring atomically. If Sieve's SSH host key is ever replaced, update its
recipient in `.sops.yaml` and rewrap `hosts/shared/telemetry-secrets.yaml`
before deploying the new key. Rerun `thornix-netbox-seed` on Atlas after
deployment to add Sieve to the authoritative inventory.

### Hound endpoint visibility and response

Hound runs Velociraptor at `https://hound.guildedthorn.arpa/`. The browser GUI
is loopback-only behind nginx and a short-lived ThornCloud_CA certificate;
firewall rules and a second nginx ACL admit only OPT1, LAN, and ThornVPN. The
separate encrypted endpoint frontend listens on TCP 8000 for enrolled clients.
Prometheus metrics on TCP 8003 accept only SOC as a source.

The checked-in Nix configuration contains policy but no Velociraptor secrets.
At first boot Hound generates its internal CA, frontend keys, gateway keys,
datastore, and a high-entropy `admin` password directly under mode-0700,
service-owned VM state. Rebuilds reapply declarative listener/resource policy
while preserving that generated trust. The service runs as an unprivileged
user under systemd hardening; nginx stays fail-closed until the administrator
record exists. First boot reissues only the generated frontend and gateway
certificates to match the internal CA's ten-year lifetime; the health timer
warns through systemd/SOC if that client-facing certificate ever falls below
30 days. Anvil's separate browser certificate still renews every 24 hours.

After CI promotes `deploy-mac` and `deploy-hound`, add a pfSense host override
for `hound.guildedthorn.arpa` at `172.16.25.57`, then provision it from mac:

```sh
ssh -A root@172.16.25.3
thornix-provision hound
```

Read the generated credential and change it immediately after the first login:

```sh
ssh root@172.16.25.57 hound-admin-password
```

No endpoint is enrolled and no hunt or response action starts automatically.
When ready to onboard a selected endpoint, export its deployment-specific
client config to a new root-only file, transfer it over SSH, and use the
platform-specific installer workflow in Velociraptor:

```sh
ssh root@172.16.25.57 \
  hound-export-client-config /root/hound-client.config.yaml
scp root@172.16.25.57:/root/hound-client.config.yaml ./
```

Treat that client config as enrollment material and do not commit it. More
critically, `/var/lib/velociraptor/server.config.yaml` contains the internal CA
private key that existing clients trust. Preserve it with the Hound datastore
in a root-only encrypted NAS backup before enrolling important endpoints; a
newly generated replacement config is a different deployment and existing
clients will not trust it.

Hound telemetry is encrypted to its SSH-derived age recipient. The dedicated
`hosts/hound/telemetry.nix` enrollment marker atomically enables Alloy, the
audit canary, node/comin/Velociraptor scrapes, HTTPS probing, and missing-log
alerts. If Hound's SSH host key is ever replaced, update its recipient in
`.sops.yaml` and rewrap `hosts/shared/telemetry-secrets.yaml` before deploying
the new key. Rerun `thornix-netbox-seed` on Atlas to materialize VM 109 and its
services in NetBox.

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

The `soc` VM (172.16.25.51) is the fleet's monitoring and SIEM hub. Every
installed/enrolled host ships logs to it, and it pulls metrics back.

**What runs where:**

- **soc**: Loki (logs, chunks in the NAS's SeaweedFS S3 `loki` bucket, 90d
  retention), Prometheus (metrics, 90d local, backed up nightly to the NAS
  via restic), and Grafana (`https://soc.guildedthorn.arpa:3000`). Loki and
  Prometheus listen on loopback only. nginx preserves the external `:3100`
  and `:9090` endpoints behind ThornCloud_CA mTLS, source-network ACLs, and
  an exact API allowlist: the fleet certificate can only ingest, while the
  workstation certificate can only query.
- **every host** (via `services-observability` + `services-audit`, both in
  `thorn-core`): `node_exporter` exposes metrics on :9100 only to the SOC,
  and auditd adds a baseline of security rules (identity/sudoers/sshd
  changes, module loads, privilege exec, and `execve`).
- **nixos, mac, scout, soc, websites, atlas, anvil, sieve, hound** (`thorn.telemetry.enable = true`):
  Grafana Alloy tails the systemd journal and pushes it to Loki using the
  fleet writer certificate. Enrollment is explicit because a host must be a
  recipient of `hosts/shared/telemetry-secrets.yaml`; there is no plaintext
  fallback for lab configurations that lack an age identity.
  `thorn.audit.execScope` controls how much `execve` is
  recorded: desktops use `"sessions"` (auid >= 1000 — real user activity
  only, since unfiltered execve on a desktop is mostly systemd churn),
  while headless hosts set `"all"`. That distinction matters — under
  `"sessions"` a server with no interactive logins records *nothing*, which
  is precisely where a compromised service would run.
- **mac, soc, websites, atlas, anvil, sieve, hound** (via
  `services-canary`): a uniquely-named
  probe runs every 10 minutes, and an alert fires if its `execve` record
  doesn't reach Loki. This is the only check that tests the detection pipeline
  instead of reporting through it — the probe emits no log output of its own, so it can
  only appear if auditd → journal → Alloy → Loki → query all work. It exists
  because a wrong LogQL filter once left every audit panel silently empty
  for weeks, indistinguishable from a quiet fleet. Requires
  `execScope = "all"` (asserted at build time).
- **nixos, soc, websites**: additionally run CrowdSec (detect-only, no
  bouncer — nothing is ever blocked), reading the journal's syslog
  transport.
- **websites**: additionally runs Suricata (af-packet IDS on `lo`+`eth0` —
  `lo` because real ingress is the Cloudflare tunnel, readable only on
  loopback). Suricata's EVE JSON ships to Loki via a second Alloy file
  source.
- **mac**: additionally runs Zeek as a passive sensor on the Proxmox `vmbr0`
  bridge. This sees guest-to-guest traffic that never reaches pfSense and
  records connection, DNS, HTTP, TLS, SSH, asset, capture-loss, and sensor
  health metadata as JSON. Alloy ships the current logs to Loki; Zeek rotates
  them daily and keeps seven local days for recovery. The sensor is capped at
  two CPUs and 4 GiB and is not inline, so stopping it cannot interrupt VM
  networking. Its high-signal policies detect SSH password guessing,
  Heartbleed activity, and observable TLS certificate failures against both
  public roots and ThornCloud_CA. Grafana inventories observed hosts/services
  and pivots matching Zeek and Suricata evidence by Community ID; selected
  notices page Discord.

**How a log becomes a graph:** journal line → Alloy (`loki.source.journal`)
→ Loki on soc → Grafana panel / alert rule. Metrics are the reverse pull:
Prometheus on soc scrapes each host's `:9100`. Both directions depend on
`<host>.guildedthorn.arpa` resolving — static hosts are pinned in
`modules/core/lan-hosts.nix`; DHCP hosts (the laptops) need a pfSense static
reservation or their Prometheus target shows down.

The two telemetry client private keys are separate from the SOC server key:

- `thornix-telemetry-writer` is shared by Alloy through
  `hosts/shared/telemetry-secrets.yaml`, encrypted to every installed host.
- `thornix-telemetry-reader` exists only in `hosts/nixos/secrets.yaml` for the
  CRT's direct read-only queries.

Both certificates must use the `clientAuth` EKU from
`certs/telemetry-client.ext`. Public certificates live at
`certs/telemetry-{writer,reader}.crt`; plaintext private keys never enter Git.
Before enrolling another host, add its age recipient to the shared creation
rule in `.sops.yaml`, run `sops updatekeys` on the shared file, and only then
set `thorn.telemetry.enable = true` in that host's secrets module.

**Dashboards & alerts** are provisioned from the repo, so they survive
rebuilds and aren't hand-clicked:

- Dashboards: `hosts/soc/dashboards/*.json` (SOC Overview, Fleet Health,
  Fleet Capacity & Performance, Service & Monitoring Health, Authentication
  & Access, Endpoint Activity, Network Visibility, Log Pipeline Health, Fleet
  Deploys), wired in via `services.grafana.provision.dashboards` — the whole
  directory is provisioned, so a new file needs no other edit.
- Alert rules: inline in `modules/computers/soc.nix` under
  `provision.alerting` (host down, unit failed, SSH brute force, Suricata
  alert, CrowdSec scenario, Loki down, disk/inode pressure, read-only roots,
  OOM kills, clock sync, stale backups, endpoint/TLS failures, comin state,
  Zeek sensor silence/capture loss, SSH password guessing, Heartbleed, local
  certificate failures, plus one log-silence rule generated per always-on
  host). All deliver to Discord via a webhook held in sops.
- Each rule carries a `severity` label (`critical` / `warning`). The
  notification policy routes both to the same Discord webhook but gives
  `critical` faster grouping and hourly re-notification, so an IDS hit
  doesn't sit behind a once-failed systemd unit.

**Deploy visibility:** Prometheus scrapes comin's metrics endpoint (`:4243`,
opened fleet-wide by `services-observability`) alongside node metrics.
`comin_deployment_info` carries the deployed commit id per host, so "is
every host running what I pushed?" is the Fleet Deploys dashboard rather
than an SSH session. Roaming hosts push the same job over remote-write.
This matters because a failed deploy is otherwise invisible — the host
stays up, keeps shipping logs, and looks healthy on every other panel
while running its previous generation.

**Outside-in failure detection:** soc cannot report its own outage, so a
five-minute `soc-deadman` timer verifies Loki, Prometheus, Grafana, Alloy,
and syslog locally before pinging Healthchecks.io. The absence of that ping
covers VM, hypervisor, power, LAN, and internet failures that Grafana cannot
observe from inside the SOC. Blackbox probes complement it with HTTP/TLS and
certificate-expiry telemetry for the public site and critical LAN services.

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
