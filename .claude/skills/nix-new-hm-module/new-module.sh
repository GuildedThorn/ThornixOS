#!/usr/bin/env bash
# Scaffolds a new modules/home-manager/<name>.nix following this repo's
# enable-flag convention (see CLAUDE.md), so the boilerplate never has to be
# re-derived by reading an existing module as a template.
#
# Usage:
#   new-module.sh <name> [description...]
#   new-module.sh <name> --desktop [description...]
#
# --desktop uses the thorn.desktop.<name>.enable namespace instead of
# thorn.programs.<name>.enable (per CLAUDE.md's convention for rice/desktop
# modules).
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: new-module.sh <name> [--desktop] [description...]" >&2
  exit 1
fi

name=$1
shift

namespace="thorn.programs"
if [ "${1:-}" = "--desktop" ]; then
  namespace="thorn.desktop"
  shift
fi

description=${*:-"Thorn's $name Home Manager configuration"}

repo_root=$(git rev-parse --show-toplevel)
out="$repo_root/modules/home-manager/$name.nix"

if [ -e "$out" ]; then
  echo "refusing to overwrite existing file: $out" >&2
  exit 1
fi

cfg_path="config.${namespace}.${name}"

cat > "$out" <<NIX
{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = ${cfg_path};
    in
    {
      options.${namespace}.${name}.enable =
        lib.mkEnableOption "${description}";

      config = lib.mkIf cfg.enable {
        # TODO: module config
      };
    };
}
NIX

echo "wrote $out"
echo "next: enable it per-host via '${namespace}.${name}.enable = true;' in hosts/<host>/home.nix"
