# TR1200 OpenWrt image

This directory contains the flake-parts module and non-secret files embedded
in the reproducible OpenWrt sysupgrade image for the Cudy TR1200 v1. The
package output is exposed by the root ThornixOS flake as `TR1200`.

## Build

```sh
nix build .#TR1200 --out-link modules/openwrt/tr1200/result
find -L modules/openwrt/tr1200/result -type f -name '*sysupgrade.bin'
```

The image includes WireGuard tooling, LuCI WireGuard integration, Travelmate,
the Travelmate LuCI application, HTTPS LuCI, CA certificates, curl, and QR
encoding support.

The current OpenWrt release is selected by the locked
`nix-openwrt-imagebuilder` input. Update deliberately with:

```sh
nix flake update openwrt-imagebuilder
nix build .#TR1200 --out-link modules/openwrt/tr1200/result
```

## Validate and install

Copy the generated `*sysupgrade.bin` to `/tmp/TR1200.bin` on the router, then
validate it before installing:

```sh
sysupgrade -T /tmp/TR1200.bin
sysupgrade /tmp/TR1200.bin
```

The second command preserves the existing OpenWrt configuration. Do not pass
`-n` until all LAN, Wi-Fi, firewall, and management-access configuration is
represented here and has been recovery-tested.

## Secrets and mutable configuration

Do not add WireGuard private keys, Wi-Fi passwords, or other credentials below
`files/`: Nix copies those files into the world-readable Nix store and firmware
artifact. Provision secrets directly on the router after flashing. Travelmate
uplinks are intentionally mutable because hotel SSIDs and captive portals are
runtime state.
