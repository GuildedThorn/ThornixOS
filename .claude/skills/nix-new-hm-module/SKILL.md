---
name: nix-new-hm-module
description: Scaffold a new modules/home-manager/<name>.nix file following this repo's enable-flag convention (options.thorn.programs.<name>.enable / thorn.desktop.<name>.enable gated by lib.mkIf). Use whenever adding a brand-new home-manager feature module, instead of reading an existing module as a template and hand-copying its boilerplate.
---

# nix-new-hm-module

CLAUDE.md documents the convention directly: every home-manager feature
module is `homeManager.modules.thorn = { options.thorn.programs.<name>.enable
= lib.mkEnableOption ...; config = lib.mkIf cfg.enable { ... }; }` (or
`thorn.desktop.<name>.enable` for desktop/rice modules), and says to "look at
an existing module ... as the template for a new one." That's a full
file-read plus hand-transcription every time — the boilerplate itself is
static and worth generating instead.

## Steps

1. Run the bundled script instead of hand-writing the skeleton:

   ```sh
   bash .claude/skills/nix-new-hm-module/new-module.sh <name> ["description"]
   bash .claude/skills/nix-new-hm-module/new-module.sh <name> --desktop ["description"]
   ```

   This writes `modules/home-manager/<name>.nix` with the correct
   `let cfg = ...` binding, option declaration, and `mkIf` guard already
   wired up. It refuses to overwrite an existing file.

2. Fill in the `# TODO: module config` body with the actual feature config
   (this is the part that's genuinely specific to the task — write it
   normally).

3. Per CLAUDE.md, nothing needs to import the new file explicitly
   (import-tree picks up every `.nix` under `modules/` automatically). Just
   toggle it on for the relevant host(s) by adding
   `thorn.programs.<name>.enable = true;` (or `thorn.desktop.<name>.enable`)
   to that host's `hosts/<host>/home.nix`.

4. After enabling it on a host, consider running the `nix-affected-build`
   skill to dry-build that host and confirm it evaluates.
