#!/usr/bin/env bash
# Prints the list of hosts (one per line) whose NixOS closure could be
# affected by the currently changed files in this repo, using the
# dendritic-pattern wiring rules from CLAUDE.md:
#   - flake.nix / modules/core/** / modules/users/** / modules/home-manager/**
#     merge into every host's evaluation unconditionally -> affects ALL hosts.
#   - hosts/<host>/** and modules/computers/<host>.nix -> affects only <host>.
#   - a named nixos.modules.<name> file -> affects whichever hosts reference
#     config.nixos.modules.<name> in modules/computers/<host>.nix.
#
# Usage:
#   affected-hosts.sh                 # changes vs HEAD (staged+unstaged+untracked)
#   affected-hosts.sh --against main  # changes vs another ref
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

all_hosts=(firewall mac mitm nixos proxmox-guest proxmox-mitm websites scout vmware-guest vmware-test)

if [ "${1:-}" = "--against" ] && [ -n "${2:-}" ]; then
  mapfile -t changed_files < <(git diff --name-only "$2"...HEAD --)
else
  mapfile -t changed_files < <(
    {
      git diff --name-only HEAD --
      git status --porcelain --untracked-files=all | sed -E 's/^.{3}//'
    } | sort -u
  )
fi

if [ ${#changed_files[@]} -eq 0 ]; then
  echo "no-changes" >&2
  exit 0
fi

declare -A affected
all_flag=0

for f in "${changed_files[@]}"; do
  case "$f" in
    flake.nix | flake.lock | modules/core/* | modules/users/* | modules/home-manager/*)
      all_flag=1
      ;;
    hosts/*/*)
      host=$(echo "$f" | cut -d/ -f2)
      affected["$host"]=1
      ;;
    modules/computers/*.nix)
      host=$(basename "$f" .nix)
      affected["$host"]=1
      ;;
    modules/*)
      names=$(grep -oE 'nixos\.modules\.[a-zA-Z0-9_-]+' "$f" 2>/dev/null | sed -E 's/^nixos\.modules\.//' | sort -u || true)
      for name in $names; do
        for host in "${all_hosts[@]}"; do
          if grep -q "config\.nixos\.modules\.$name\b" "modules/computers/$host.nix" 2>/dev/null; then
            affected["$host"]=1
          fi
        done
      done
      ;;
  esac
done

if [ "$all_flag" = "1" ]; then
  echo "# core/user/home-manager change detected — all hosts affected" >&2
  printf '%s\n' "${all_hosts[@]}"
elif [ ${#affected[@]} -eq 0 ]; then
  echo "# no host-affecting changes detected among:" >&2
  printf '  %s\n' "${changed_files[@]}" >&2
else
  printf '%s\n' "${!affected[@]}" | sort
fi
