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
encoding support. On first boot it assigns the LAN `172.20.120.1/24`; clients
use `172.20.120.0/24`, which keeps them distinct from the router's privileged
WireGuard address and avoids the home LAN's `192.168.1.0/24`.

The router advertises Pixie network boot only while `wg0` can reach the home
WireGuard gateway and has completed a handshake within the last 180 seconds. Legacy BIOS clients receive
`undionly.kpxe`, x86-64 UEFI clients receive `ipxe.efi`, and existing iPXE
clients chain directly to `http://172.16.25.53/boot.ipxe`. The router fetches
the two bootstrap binaries from Pixie over HTTP and serves them locally over
TFTP, avoiding dynamic TFTP data channels across WireGuard. Ordinary DHCP
continues unchanged when WireGuard is unavailable.

DNS follows the same handshake state. A healthy tunnel uses only the two home
Technitium resolvers (`172.16.25.66` and `172.16.25.2`); without a fresh
handshake, dnsmasq uses `1.1.1.1` through a route pinned to the travel uplink.
Travelmate manages uplink Wi-Fi only; netifd owns `wg0` so Travelmate cannot
delete the persistent WireGuard interface during an uplink transition.

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

## WireGuard provisioning

The router is peer `10.10.10.5`. Its attached clients retain addresses from
`172.20.120.0/24`; do not enable masquerading on the `homevpn` firewall zone.
This ensures only traffic originating on the router receives administrative
access at home.

Provision the router private key and the matching `wireguard_psk_tr1200` value
through a root-only channel, then place them temporarily in
`/root/wg-private-key` and `/root/wg-preshared-key` with mode `0600`. Configure
the tunnel with:

```sh
umask 077
WG_PRIVATE_KEY="$(cat /root/wg-private-key)"
WG_PRESHARED_KEY="$(cat /root/wg-preshared-key)"

uci -q delete network.wg_home
uci -q delete network.home_peer
uci -q delete firewall.homevpn
uci -q delete firewall.lan_homevpn

uci -q batch <<EOF
set network.lan.ipaddr='172.20.120.1'
set network.lan.netmask='255.255.255.0'

set network.cloudflare_dns='route'
set network.cloudflare_dns.interface='trm_wwan'
set network.cloudflare_dns.target='1.1.1.1/32'

set network.wg_home='interface'
set network.wg_home.proto='wireguard'
set network.wg_home.private_key='$WG_PRIVATE_KEY'
add_list network.wg_home.addresses='10.10.10.5/32'

set network.home_peer='wireguard_wg_home'
set network.home_peer.description='ThornixOS firewall'
set network.home_peer.public_key='+4jlbw4WepYylpUPk36tV+9G6ny+Px8vslzuRPoD/So='
set network.home_peer.preshared_key='$WG_PRESHARED_KEY'
set network.home_peer.endpoint_host='205.178.64.45'
set network.home_peer.endpoint_port='4501'
set network.home_peer.persistent_keepalive='25'
set network.home_peer.route_allowed_ips='1'
add_list network.home_peer.allowed_ips='0.0.0.0/0'

set firewall.homevpn='zone'
set firewall.homevpn.name='homevpn'
set firewall.homevpn.input='REJECT'
set firewall.homevpn.output='ACCEPT'
set firewall.homevpn.forward='REJECT'
set firewall.homevpn.masq='0'
set firewall.homevpn.mtu_fix='1'
add_list firewall.homevpn.network='wg_home'

set firewall.lan_homevpn='forwarding'
set firewall.lan_homevpn.src='lan'
set firewall.lan_homevpn.dest='homevpn'

commit network
commit firewall
EOF

unset WG_PRIVATE_KEY WG_PRESHARED_KEY
rm -f /root/wg-private-key /root/wg-preshared-key
service network restart
service firewall restart
```

The network restart changes the router's management address. Reconnect at
`https://172.20.120.1/` and renew the client's DHCP lease if necessary.

The endpoint is the same fixed address used by Scout. Update both router
configurations if it changes.

Verify the tunnel and the source-address separation after provisioning:

```sh
wg show wg_home
ip route get 10.10.10.1
uci show firewall.homevpn
```

From an attached client, confirm Internet and intended non-administrative home
services work, then confirm SSH and privileged management ports are rejected.
On the firewall, `wg show wg0` should report `10.10.10.5/32` and
`172.20.120.0/24` for the TR1200 peer.
