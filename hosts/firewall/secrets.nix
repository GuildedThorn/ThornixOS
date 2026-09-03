{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;

  # Preserve pfSense's SSH host key during installation. Its corresponding
  # age recipient encrypts this file and avoids changing the known-host key.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets = {
    wireguard_private_key = {
      mode = "0400";
      restartUnits = [ "systemd-networkd.service" ];
    };
    wireguard_psk_scout = {
      mode = "0400";
      restartUnits = [ "systemd-networkd.service" ];
    };
    wireguard_psk_phone = {
      mode = "0400";
      restartUnits = [ "systemd-networkd.service" ];
    };
    wireguard_psk_mitospha = {
      mode = "0400";
      restartUnits = [ "systemd-networkd.service" ];
    };
    wireguard_psk_tr1200 = {
      mode = "0400";
      restartUnits = [ "systemd-networkd.service" ];
    };
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.10.10.1/24" ];
    listenPort = 4501;
    mtu = 1420;
    privateKeyFile = config.sops.secrets.wireguard_private_key.path;
    peers = [
      {
        # Scout
        publicKey = "8qsQBLB1ufuiBEntznRwPT0QshmrJmO3MVwf0mUrNV0=";
        presharedKeyFile = config.sops.secrets.wireguard_psk_scout.path;
        allowedIPs = [ "10.10.10.4/32" ];
      }
      {
        # Phone
        publicKey = "Oe2u4ctFIhv8Ym2x6m/yIkAoRqFaR+Gd4Gam8oVoY3o=";
        presharedKeyFile = config.sops.secrets.wireguard_psk_phone.path;
        allowedIPs = [ "10.10.10.2/32" ];
      }
      {
        # Mitospha
        publicKey = "QD3Ia5lK8PJEeHCH3Z8JXNfJZkVEJsbd+PvxWxxQUSc=";
        presharedKeyFile = config.sops.secrets.wireguard_psk_mitospha.path;
        allowedIPs = [ "10.10.10.3/32" ];
      }
      {
        # TR1200 travel router
        publicKey = "FxvnvepUwy94jW3BOet3FKKMqLuYg/UiRBa71OlqsXE=";
        presharedKeyFile = config.sops.secrets.wireguard_psk_tr1200.path;
        # Preserve client source addresses so attached devices do not inherit
        # the router's administrative access as 10.10.10.5.
        allowedIPs = [
          "10.10.10.5/32"
          "172.20.120.0/24"
        ];
      }
    ];
  };
}
