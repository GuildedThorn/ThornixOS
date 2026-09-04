# AP3000 OpenWrt image

This directory contains the flake-parts module for a reproducible OpenWrt
sysupgrade image for the indoor Cudy AP3000 v1. The package output is exposed
by the root ThornixOS flake as `AP3000`.

The image includes a mesh-capable WPA stack, usteer and its LuCI application,
HTTPS LuCI, LLDP and its LuCI application, tcpdump-mini, and iperf3. It supports
wired backhaul and optional encrypted 802.11s backhaul, but deliberately enables
neither mesh nor custom wireless networks at boot. Usteer and the WPA package's
optional RADIUS helper also remain disabled until explicitly configured.

## Build

```sh
nix build .#AP3000 --out-link modules/openwrt/ap3000/result
find -L modules/openwrt/ap3000/result -type f -name '*sysupgrade.bin'
```

The current OpenWrt release is selected by the locked
`nix-openwrt-imagebuilder` input. Update deliberately with:

```sh
nix flake update openwrt-imagebuilder
nix build .#AP3000 --out-link modules/openwrt/ap3000/result
```

## Configure

Provision SSIDs, VLANs, management addressing, and Wi-Fi or mesh credentials
after flashing. Secrets must not be added to this directory because Nix copies
source files into the world-readable Nix store and firmware artifact.

Provision a fresh installation through a directly connected, isolated Ethernet
client before attaching it to the production LAN. OpenWrt initially uses
`192.168.1.1`, runs a LAN DHCP server, and has no root password. Set the root
password and management address, then disable the AP's DHCP server before
connecting its backhaul to an existing network.

Use Ethernet as the primary backhaul. Do not bridge live Ethernet and 802.11s
paths into the same layer-2 network without an explicit loop-prevention or
failover design. A package-only image leaves this choice inactive and safe.

After configuring roaming policy, activate usteer with:

```sh
/etc/init.d/usteer enable
/etc/init.d/usteer start
```

## Validate and upgrade

This output is a sysupgrade image for an AP3000 v1 already running OpenWrt. It
is not Cudy factory or intermediary firmware. Copy the generated image to the
AP and validate it before upgrading:

```sh
sysupgrade -T /tmp/AP3000.bin
sysupgrade /tmp/AP3000.bin
```

The second command preserves the existing OpenWrt configuration. Do not pass
`-n` until LAN, Wi-Fi, firewall, and management access are recovery-tested.

For first installation from Cudy firmware, verify the label says AP3000 v1 and
follow the AP3000 v1 installation procedure. The intermediary archive supplied
by Cudy instructs upgrading stock firmware to 2.4.7, installing its intermediary
image, and only then installing an AP3000 v1 OpenWrt sysupgrade image. Never
flash this image directly from stock firmware or onto Outdoor/Wall variants.
