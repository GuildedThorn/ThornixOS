{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  # The ZIM is a manual download; it is deliberately not part of the Nix store.
  # Download it to this path before activating this module:
  #   sudo curl -L -C - -o /platter/services/kiwix/wikipedia_en_all_maxi_2026-08.zim \
  #     https://download.kiwix.org/zim/wikipedia/wikipedia_en_all_maxi_2026-08.zim
  zimDir = "/platter/services/kiwix";
  zimFile = "${zimDir}/wikipedia_en_all_maxi_2026-08.zim";
  port = 8082;
  mitmAddress = "172.16.25.2";
in
{
  assertions = [
    {
      assertion = config.networking.hostName == "granite";
      message = "services-wiki is currently intended for the granite host";
    }
  ];

  users.groups.kiwix = { };
  users.users.kiwix = {
    isSystemUser = true;
    group = "kiwix";
    home = "/var/lib/kiwix";
    createHome = true;
    description = "Kiwix ZIM server";
  };

  systemd.tmpfiles.rules = [
    "d ${zimDir} 0755 root root -"
    "d /var/lib/kiwix 0700 kiwix kiwix -"
  ];

  # A dedicated unit instead of services.kiwix-serve: the upstream module uses
  # linkFarm for its `library` option, which would copy the 119 GiB ZIM into the
  # Nix store. Running here, next to platter, also keeps libzim's memory-mapped
  # random reads off the LAN. MITM owns the TLS vhost and proxies to this port.
  systemd.services.kiwix-serve = {
    description = "Kiwix HTTP server (offline Wikipedia)";
    after = [
      "network.target"
      "zfs-import-platter.service"
      "zfs-mount.service"
    ];
    requires = [ "zfs-mount.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "exec";
      User = "kiwix";
      Group = "kiwix";
      Restart = "on-failure";
      RestartSec = 5;
      ExecStartPre = "${pkgs.coreutils}/bin/test -r ${lib.escapeShellArg zimFile}";
      ExecStart = utils.escapeSystemdExecArgs [
        "${pkgs.kiwix-tools}/bin/kiwix-serve"
        "--address"
        "ipv4"
        "--port"
        (toString port)
        zimFile
      ];
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ zimDir ];
    };
  };

  # Only MITM may reach the backend; it terminates TLS for wiki.guildedthorn.arpa.
  networking.firewall.extraCommands = ''
    iptables -w -A nixos-fw -p tcp -s ${mitmAddress}/32 \
      --dport ${toString port} -j nixos-fw-accept
  '';
}
