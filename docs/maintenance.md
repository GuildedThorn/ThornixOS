# Maintaining ThornixOS

## Finding configuration

Start with `modules/computers/<host>.nix`. It composes a machine from named
profiles, reusable services, hardware modules, and files in `hosts/<host>/`.
Follow the explicit imports to find where a setting comes from.

Keep the composition file short: select named modules and import machine
settings from `hosts/<host>/system.nix`, networking from `networking.nix`, disks
from `disko.nix`, and user preferences from `home.nix`. Split a large machine
module by the service or subsystem a maintainer would look for, rather than by
an arbitrary line limit. A module used by only one host can stay with that host.

Host-specific service deployments live in `hosts/<host>/<service>/default.nix`,
beside their Compose files, scripts, and tests. The host composition imports
these directories directly. `modules/services/` contains integrations intended
for reuse across machines, such as backup, telemetry, and endpoint agents.

Loom's n8n directory keeps its four bootstrap scripts separate from service
configuration. `replaceVarsWith` fills explicit store paths into executable
templates and checks substitutions; ShellCheck validates the rendered scripts.
Its bootstrap tests use disposable state and mock PostgreSQL/n8n commands,
including malformed-secret, credential-rotation, and import-idempotence cases.

`lib/compose-stack.nix` shares Compose start/stop locking, config validation,
and administrator commands across Greenbone, TheHive, and OpenCTI. Each host
still owns its readiness gates, secrets, updates, backups, and application
settings. OpenCanary retains its distinct start sequence, which waits for a
real decoy listener before declaring the unit ready.

`flake.nix` declares external inputs. `import-tree` loads every Nix file under
`modules/` as a **flake-parts module**. A file placed there must therefore define
flake-parts options such as `nixos.modules`, `homeManager.modules`, `perSystem`,
or `flake`; it must not be a bare NixOS module. Put ordinary host modules and
data under `hosts/`, helper functions under `lib/`, and packages under `packages/`.
Those directories are imported explicitly.

## Module conventions

- Keep host composition explicit; put a feature shared by machines in
  `modules/services/` or a profile in `modules/profiles/`.
- Export reusable NixOS modules through `nixos.modules.<name>`, and Home Manager
  modules through `homeManager.modules.<name>`. These are deferred modules,
  which can accept NixOS or Home Manager arguments when composed.
- Use relative paths for local module imports so editors can navigate them.
  Use input paths for external sources and strings when a runtime path is needed.
  Host modules that need flake inputs receive them through `_module.args.inputs`
  in the composition file. Keep imports independent of those late module
  arguments; choose external modules in the composition file instead.
- Use `lib.mkDefault` for defaults intended for host overrides. Reserve
  `lib.mkForce` for settings whose normal merge behavior cannot express intent.
- Explain hardware workarounds, upstream pins, and surprising choices. Remove
  commented experiments when they no longer explain a current requirement.
- Keep secrets encrypted with SOPS. Never put credentials in Nix expressions:
  evaluation and builds copy source and generated files into the Nix store.
- Treat `vendor/` as upstream code; formatting and lint checks exclude it.

## Adding or changing a host

1. Add its entry to `hosts/inventory.nix`, including architecture, deployment,
   and monitoring policy. This is the authoritative fleet membership.
2. Create `hosts/<name>/` with its networking, storage, and other host modules.
   Reuse a suitable hardware module or supply the machine's generated hardware
   configuration. Review disk layouts before installation.
3. Add `modules/computers/<name>.nix` with an explicit module list, selecting
   profiles and services. Take `nixpkgs.hostPlatform` from its inventory entry.
4. Add encrypted secrets, SSH recipients, recovery contracts, and service catalog
   entries as appropriate. Preserve conditional readiness checks used during
   initial provisioning.
5. Run formatting, source checks, and fleet evaluation, then build the affected
   host's system closure. Evaluation alone does not prove packages will build.

## Local validation

Run these commands from the repository root:

```sh
nix develop
nix fmt
nix build .#checks.x86_64-linux.{nixfmt,statix,deadnix,shellcheck,compose-stack} --no-link
bash scripts/check-fleet
nix build .#nixosConfigurations.<host>.config.system.build.toplevel --no-link
```

`scripts/check-fleet` checks inventory membership and architecture, then evaluates
each system's derivation in a fresh Nix process. This bounds memory usage across
the fleet. Add new files to Git before evaluating: Git flakes only include
tracked files. CI runs the same script and separately verifies the checked-out
Git revision stamp. `THORNIX_FLAKE` can select a separate source snapshot for
evaluation without changing the script.

`nix fmt -- --check` checks formatting without rewriting files. `nix develop`
provides nixfmt, Statix, deadnix, and ShellCheck from the locked nixpkgs input.
For shell changes, run `shellcheck scripts/check-fleet`.

The Compose lifecycle check uses a mock command and checks argument quoting,
lock contention, root-only administration, and volume-preserving shutdown.
Service-specific checks remain attached to their host's `system.checks`, so
Hydra runs them when building that system closure.

The fleet script covers NixOS systems. When changing shared flake plumbing,
also evaluate the standalone Home Manager configuration and firmware outputs:

```sh
nix eval --raw '.#homeConfigurations."thorn@remote".activationPackage.drvPath'
nix eval --raw .#packages.x86_64-linux.AP3000.drvPath
nix eval --raw .#packages.x86_64-linux.TR1200.drvPath
nix eval --raw .#packages.x86_64-linux.TR1200-finix.drvPath
```

For an unstaged working tree containing new files, use `path:.` in place of `.`
in flake references, for example `THORNIX_FLAKE=path:. bash scripts/check-fleet`.
This includes untracked source files without changing the Git index. Review
the working tree first: path flakes include local files that Git flakes omit.

## Updating dependencies

Update a focused input with `nix flake update <input-name>`. Review both
`flake.nix` and `flake.lock`; compatibility pins may be deliberate. Run the
validation workflow and inspect evaluation warnings for renamed or removed
options. Build affected machines before promotion. A full `nix flake update`
updates all unlocked inputs and needs correspondingly broad build validation.

Keep `system.stateVersion` and `home.stateVersion` at their existing values
unless performing a reviewed data migration. They select compatibility defaults,
not the installed package release. See the
[NixOS state version guidance](https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion).

Host activation is a separate operation from cleanup or evaluation. Follow the
existing Hydra and `production` promotion workflow described in the README.

## Compatibility decisions

See [Upstream packaging and workarounds](upstream-workarounds.md) for the latest
audit of local packages, removed overrides, and remaining upstream gaps.

The modern platform setting is `nixpkgs.hostPlatform`; each computer takes it
from the inventory. The rest of the configuration follows the
[NixOS module system](https://nixos.org/manual/nixos/unstable/#sec-writing-modules):
explicit imports, normal option merging, and overridable defaults.

Before removing a pin or override, read its nearby comment and validate the
affected closure. In particular, Raspberry Pi audio uses a separate stable
kernel, the capture workstation and storage server pin kernel versions, Hyprland
shares nixpkgs with the system's Qt plugins, and Proxmox PAM uses its stable
package set. These are compatibility choices, not interchangeable style fixes.
