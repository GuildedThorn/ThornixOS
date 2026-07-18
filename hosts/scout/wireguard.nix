{ config, ... }:
{
  # Road-warrior WireGuard back to pfSense. Full-tunnel (all traffic routed
  # home when connected: LAN access + protection on hostile networks + SOC
  # telemetry reaches soc over the tunnel).
  #
  # ON DEMAND, not auto-started (autostart = false). scout is sometimes
  # physically on the home LAN, and an always-up tunnel there would try to
  # reach the WAN IP from inside the network (a hairpin pfSense won't do) —
  # the handshake fails but the routes are already installed, black-holing
  # traffic. So bring it up only when remote:
  #   sudo systemctl start wg-quick-wg0     # connect  (or `wg-quick up wg0`)
  #   sudo systemctl stop  wg-quick-wg0     # disconnect
  #   systemctl is-active  wg-quick-wg0     # status
  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.10.10.3/32" ];
    dns = [ "10.10.10.1" ]; # pfSense over the tunnel — resolves .arpa names
    privateKeyFile = config.sops.secrets.wg_private_key.path;
    autostart = false;
    peers = [
      {
        publicKey = "+4jlbw4WepYylpUPk36tV+9G6ny+Px8vslzuRPoD/So=";
        presharedKeyFile = config.sops.secrets.wg_preshared_key.path;
        endpoint = "205.178.64.45:4501";
        allowedIPs = [ "0.0.0.0/0" ];
        persistentKeepalive = 25;
      }
    ];
  };
}
