# Upstream packaging and workarounds

Reviewed against the repository's locked inputs on 2026-11-10. A package being
available upstream does not imply its NixOS module supports this deployment's
configuration format, state paths, hardware, or credentials.

## Removed in this review

| Local implementation | Upstream replacement or reason for removal |
|---|---|
| `packages/n8n.nix`, version 2.35.4 | The locked `pkgs.n8n` is 2.39.6 and includes JavaScript and Python task runners. The original security advisory, GHSA-mwp5-2m32-r54h, is fixed in 2.35.4 and 2.36.2 or later. All workflow commands now use `config.services.n8n.package`. |
| Graphify 0.9.43 wheel and source input | `pkgs.graphify` packages 0.9.91, including tree-sitter grammars. This removes the Graphify-specific runtime uv installation; the local OpenCode policy and reminder remain. |
| Arc theme variant override | The locked package carries `meson_1.12.patch`, fixing the directory entries in GNOME resource dependencies that caused the original build failure. |
| kingfisher install-check override | The workaround targeted 1.113.0. The locked package is 2.14.0 and no longer declares that install check. |
| ltrace test suppression | Use the unmodified upstream package, including its current GCC/glibc test fixes and enabled check phase. |
| anyio/private NetExec Python overlay | The locked anyio is 4.15.1, with upstream fixes and test exclusions. Remove the old 4.14.2-specific override and verify the upstream NetExec closure. |
| torchcodec overlay in the Ollama profile | It existed to build Open WebUI, which is disabled. The unrelated Python package override does not belong in the active Ollama configuration. |
| Suricata `ProtectProc` override | The locked NixOS module already sets `ProtectProc = "invisible"`. |
| Authentik distribution name override | The locked package already names its bundled Python distribution `authentik`. Other workspace/dependency metadata fixes remain. |
| Proxmox XML-Twig patch removal | Its locked stable package no longer includes the offending patch, so the empty-patch override is redundant. |

The n8n and Graphify replacements also upgrade those applications. Package
builds and configuration evaluation do not exercise an existing n8n database
or every Graphify workflow. Follow normal backup and promotion procedures
before activating the application update.

## Retained: upstream gap or separate compatibility requirement

| Area | Why it was retained / what must change before removal |
|---|---|
| Stalwart service | The locked NixOS module still generates the older TOML configuration. Courier uses 0.16's mutable JSON datastore pointer and API-managed configuration; packaging 0.16 alone does not replace that service definition. |
| Stalwart RocksDB override | Retained pending a runtime database/compaction check. The locked 0.16 package still links system RocksDB; a newer application version alone does not prove the previous ABI failure is resolved. |
| DisplayLink | The upstream module is selected through Xorg video drivers and adds Xorg session setup. The local Wayland unit also supplies an automatically fetched vendor archive in place of `requireFile`. |
| Velociraptor | No matching package or NixOS module was found in the locked source. Keep the pinned binary package and deployment-specific client/server setup. |
| Linux Voice Assistant and microWakeWord dependencies | No matching application, pymicro-features, or pymicro-wakeword package was found in the locked source. The existing Wyoming satellite module is a different protocol/application. |
| Wyoming Kokoro | Kokoro's Python library is packaged; the local Wyoming protocol server and voice routing are separate functionality. |
| Hashtopolis | No matching agent/server package or module was found in the locked source. Keep agent packaging, CA handling, secret bootstrap, and the container deployment. |
| TheHive, OpenCTI, Greenbone, OpenCanary | No matching full service modules were found in the locked source. Individual dependencies such as greenbone-feed-sync do not replace the complete stacks. |
| Zeek sensor | Zeek is packaged, but no matching NixOS service module was found in the locked source. Capture policy, private CA handling, and topology export remain local integration. |
| Reposilite external storage | The upstream module still creates a StateDirectory only for direct children of `/var/lib`. Granite's ZFS path needs explicit directory creation and write access. |
| nixos-anywhere SSH patch | Upstream still places disabled host-key checking before caller-provided SSH options. Keep the patch until upstream supports strict known-host handling without conflicting defaults. |
| Proxmox package/PAM compatibility | Proxmox uses a separate stable package set. Verify fixes against that exact input, including the PVE tools and PAM login, before removing its package overrides. |
| Matcha mail patch | The packaged 1.1.0 source still returns from failed OAuth/password authentication without closing the connection. Retain the patch; Gmail Trash and concurrent-action behavior also need individual verification before removing their changes. |
| Authentik metadata overrides | The locked package still assigns the application release version to bundled workspace packages. Keep those fixes until the metadata and build hooks agree. |
| Graphify launch wrapper | Native 0.9.91's extraction command re-execs a bare Python interpreter and loses nixpkgs' module path. Set its intended default `PYTHONHASHSEED=0` before launch; retain only this small wrapper. |
| sc0710 firmware and kernel pins | Hardware-specific compatibility choices. A packaged driver does not supply the vendored FPGA image or prove operation with a different kernel. |
| Firewall serial ISO modification | The installer changes COM1/ttyS0 assumptions to COM2/ttyS1. Remove it only when upstream ISO options cover both BIOS and EFI serial menus. |
| OpenWrt index hashes | Release package indexes are mutable. Keep explicit hashes until the pinned ImageBuilder data matches the release indexes. |

## Reviewing future updates

Start with the locked package definition and module, then inspect upstream
changes. Prefer the normal `services.<name>.package` option over copying an
entire derivation. Delete a compatibility override only after checking the
specific failure it addressed, rather than merely comparing version numbers.

Keep local fleet policy, credentials, monitoring, backup contracts, and
application bootstrap separate from missing upstream packaging. These may
still be needed after the underlying package or service gains upstream support.

Sources: [n8n package](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/n8/n8n/package.nix),
[n8n advisory](https://github.com/n8n-io/n8n/security/advisories/GHSA-mwp5-2m32-r54h),
[Graphify package](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/gr/graphify/package.nix),
[Stalwart module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/mail/stalwart.nix),
[DisplayLink module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/hardware/video/displaylink.nix).
These upstream links move; the audit findings refer to the repository's lock.
