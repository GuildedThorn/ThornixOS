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

mapfile -t all_hosts < <(
	for path in modules/computers/*.nix; do
		file=${path##*/}
		printf '%s\n' "${file%.nix}"
	done | sort
)

if [ ${#all_hosts[@]} -eq 0 ]; then
	echo "no NixOS configurations found under modules/computers" >&2
	exit 1
fi

base_commit=HEAD
if [ $# -gt 0 ]; then
	if [ "$1" != "--against" ] || [ $# -ne 2 ]; then
		echo "usage: affected-hosts.sh [--against <ref>]" >&2
		exit 2
	fi
	if ! against_commit=$(git rev-parse --verify "$2^{commit}" 2>/dev/null); then
		echo "invalid git ref: $2" >&2
		exit 2
	fi
	base_commit=$(git merge-base "$against_commit" HEAD)
	mapfile -t changed_files < <(
		{
			git diff --name-only "$base_commit" --
			git ls-files --others --exclude-standard
		} | sort -u
	)
else
	mapfile -t changed_files < <(
		{
			git diff --name-only HEAD --
			git ls-files --others --exclude-standard
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
	flake.nix | flake.lock | .sops.yaml | certs/* | lib/* | packages/* | \
		hosts/inventory.nix | hosts/service-catalog.nix | hosts/backup-catalog.nix | \
		hosts/shared/* | modules/core/* | modules/users/* | modules/home-manager/*)
		all_flag=1
		;;
	hosts/*/*)
		host=${f#hosts/}
		host=${host%%/*}
		if [ -f "modules/computers/$host.nix" ]; then
			affected["$host"]=1
		else
			all_flag=1
		fi
		;;
	modules/computers/*.nix)
		host=$(basename "$f" .nix)
		affected["$host"]=1
		;;
	modules/*)
		if [[ "$f" != *.nix ]] || [ ! -f "$f" ]; then
			all_flag=1
			continue
		fi
		current_names=$(grep -oE 'nixos\.modules\.[a-zA-Z0-9_-]+' "$f" 2>/dev/null || true)
		base_names=$(git show "$base_commit:$f" 2>/dev/null | grep -oE 'nixos\.modules\.[a-zA-Z0-9_-]+' || true)
		names=$(
			printf '%s\n%s\n' "$current_names" "$base_names" |
				sed -E '/^$/d; s/^nixos\.modules\.//' |
				sort -u
		)
		if [ -z "$names" ]; then
			all_flag=1
			continue
		fi
		for name in $names; do
			matched=0
			if grep -R -q --include='*.nix' \
				--exclude-dir=computers --exclude-dir=core --exclude-dir=users \
				"config\.nixos\.modules\.$name\b" modules 2>/dev/null; then
				# Another named module wraps this one. Without recursively resolving
				# the module graph, all-host is the only safe answer.
				all_flag=1
				matched=1
			fi
			if grep -q "config\.nixos\.modules\.$name\b" modules/core/*.nix modules/users/*.nix 2>/dev/null; then
				all_flag=1
				matched=1
			fi
			for host in "${all_hosts[@]}"; do
				if grep -q "config\.nixos\.modules\.$name\b" "modules/computers/$host.nix" 2>/dev/null; then
					affected["$host"]=1
					matched=1
				fi
			done
			if [ "$matched" = "0" ]; then
				# Wrapper dependencies are handled conservatively rather than
				# risking an under-build when no direct host reference exists.
				all_flag=1
			fi
		done
		;;
	esac
done

if [ "$all_flag" = "1" ]; then
	echo "# shared or fleet-wide change detected - all hosts affected" >&2
	printf '%s\n' "${all_hosts[@]}"
elif [ ${#affected[@]} -eq 0 ]; then
	echo "# no host-affecting changes detected among:" >&2
	printf '  %s\n' "${changed_files[@]}" >&2
else
	printf '%s\n' "${!affected[@]}" | sort
fi
