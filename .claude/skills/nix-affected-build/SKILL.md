---
name: nix-affected-build
description: Dry-build only the NixOS hosts actually affected by current changes. Use this instead of guessing host impact whenever editing modules/ or hosts/.
---

# nix-affected-build

This repo is a flake-parts + import-tree ("dendritic pattern") NixOS config
whose fleet is declared under `modules/computers/`. CLAUDE.md calls out the risk directly: "When editing a
module used by multiple hosts, dry-build each affected host, not just one."
Guessing wrong wastes a full closure build's worth of tokens/time either by
under-checking (miss a broken host) or over-checking (rebuild every host when
only 2 use the module you touched).

## Steps

1. Run the bundled script to compute the affected host set from the current
   git diff (staged + unstaged + untracked, vs HEAD by default):

   ```sh
   bash .claude/skills/nix-affected-build/affected-hosts.sh
   ```

   Pass `--against <ref>` (e.g. `--against main`) to diff against a branch
   instead of HEAD. The script encodes the wiring rules itself — you do not
   need to re-derive which hosts import which module by reading files.

2. If it reports "all hosts affected" (a change under `modules/core/`,
   `modules/users/`, `modules/home-manager/`, or `flake.nix`/`flake.lock` —
   these merge into every host's evaluation unconditionally), or if it
   reports "no host-affecting changes detected", say so plainly and use
   judgment: for a true all-hosts change, building all hosts is warranted; for
   no detected impact, a doc/comment-only change likely needs no build. Host
   membership is derived dynamically from `modules/computers/*.nix`.

3. Otherwise, dry-build only the listed hosts, in parallel where possible:

   ```sh
   nix build ".#nixosConfigurations.<host>.config.system.build.toplevel" --no-link
   ```

4. Report a compact pass/fail table, one line per host. Do NOT dump full
   build output into the conversation. On failure, show only the last
   ~20 lines of that host's build output (the actual error), not the full
   log.

## Why this exists

A single host's `nix build` closure can emit tens of thousands of tokens of
build log if shown in full, and this repo's CI evaluates the full fleet on every
push — mirroring that locally by default is the expensive path. Scoping to
the actually-affected set, and only surfacing logs on failure, is the cheap
path that still catches the real risk (breaking a host you didn't mean to
touch).
