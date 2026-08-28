{ config, ... }:
let
  # Road-warrior WireGuard back to the firewall, in two flavors sharing one
  # identity (same keys/IP, so the firewall sees a single peer either way):
  #   wg0 — FULL tunnel: all traffic routed home for protection on hostile
  #         networks, SOC telemetry, and approved internal services.
  #   wg1 — SPLIT tunnel: OPT1 is routed, but the firewall admits only
  #         approved services; internet stays local (faster, no MTU tax).
  # Only one can be up at a time — the units Conflict, so starting one
  # stops the other:
  #   vpn-full / vpn-split / vpn-off / vpn-status   (aliases below)
  #
  # ON DEMAND, not auto-started (autostart = false). scout is sometimes
  # physically on the home LAN, and an always-up tunnel there would try to
  # reach the WAN IP from inside the network (hairpin routing is disabled) —
  # the handshake fails but the routes are already installed, black-holing
  # traffic. So bring it up only when remote.
  peer = allowedIPs: {
    inherit allowedIPs;
    publicKey = "+4jlbw4WepYylpUPk36tV+9G6ny+Px8vslzuRPoD/So=";
    presharedKeyFile = config.sops.secrets.wg_preshared_key.path;
    endpoint = "205.178.64.45:4501";
    persistentKeepalive = 25;
  };
  iface = {
    address = [ "10.10.10.4/32" ];
    # The firewall over the tunnel resolves .arpa names. Set for both modes:
    # split still needs it for LAN name resolution, at the cost of all DNS
    # queries riding the tunnel.
    dns = [ "10.10.10.1" ];
    privateKeyFile = config.sops.secrets.wg_private_key.path;
    autostart = false;
    # 1280 instead of wg-quick's default 1420: cellular hotspots drop
    # full-size encapsulated packets (PMTUD black hole — TLS handshakes
    # stall while pings pass). 1280 is the always-works floor for a
    # laptop that roams across arbitrary networks.
    mtu = 1280;
  };
in
{
  networking.wg-quick.interfaces = {
    wg0 = iface // {
      peers = [ (peer [ "0.0.0.0/0" ]) ];
    };
    # Home subnets only. Deliberately NOT 192.168.1.0/24 (the firewall LAN
    # side): hotspots use that range constantly and a tunnel route for it
    # would fight the local network scout is actually sitting on.
    wg1 = iface // {
      peers = [
        (peer [
          "10.10.10.0/24"
          "172.16.25.0/24"
        ])
      ];
    };
  };

  systemd.services."wg-quick-wg0".unitConfig.Conflicts = [ "wg-quick-wg1.service" ];
  systemd.services."wg-quick-wg1".unitConfig.Conflicts = [ "wg-quick-wg0.service" ];

  environment.shellAliases = {
    vpn-full = "sudo systemctl start wg-quick-wg0";
    vpn-split = "sudo systemctl start wg-quick-wg1";
    vpn-off = "sudo systemctl stop wg-quick-wg0 wg-quick-wg1";
    vpn-status = "sudo wg show";
  };
}
