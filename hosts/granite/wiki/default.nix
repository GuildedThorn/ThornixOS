{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  # ZIMs are manual downloads; they are deliberately not part of the Nix store.
  # Wikipedia is required; the rest are optional and are skipped by
  # --skipInvalid until downloaded. Add filenames below, then restart
  # kiwix-serve to pick them up. Fetch each from its Kiwix area:
  #   curl -L -C - -o /platter/services/kiwix/<file> \
  #     https://download.kiwix.org/zim/<wikipedia|stack_exchange|ifixit|devdocs>/<file>
  zimDir = "/platter/services/kiwix";
  zimNames = [
    "wikipedia_en_all_maxi_2026-08.zim"
    # Practical troubleshooting Q&A, complementary to Wikipedia's summaries.
    "serverfault.com_en_all_2026-10.zim"
    "unix.stackexchange.com_en_all_2026-10.zim"
    "superuser.com_en_all_2026-10.zim"
    # Step-by-step repair procedures.
    "ifixit_en_all_2025-12.zim"
    # API docs that Wikipedia does not carry.
    "devdocs_en_bash_2026-10.zim"
    "devdocs_en_css_2026-10.zim"
    "devdocs_en_docker_2026-10.zim"
    "devdocs_en_git_2026-10.zim"
    "devdocs_en_go_2026-10.zim"
    "devdocs_en_javascript_2026-10.zim"
    "devdocs_en_kubernetes_2026-10.zim"
    "devdocs_en_nginx_2026-10.zim"
    "devdocs_en_nix_2026-10.zim"
    "devdocs_en_postgresql_2026-10.zim"
    "devdocs_en_python_2026-10.zim"
    "devdocs_en_rust_2026-10.zim"
    "devdocs_en_terraform_2026-10.zim"
    "devdocs_en_typescript_2026-10.zim"
  ];
  zimFiles = map (name: "${zimDir}/${name}") zimNames;
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
    description = "Kiwix HTTP server (offline reference library)";
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
      ExecStartPre = "${pkgs.coreutils}/bin/test -r ${lib.escapeShellArg (builtins.head zimFiles)}";
      ExecStart = utils.escapeSystemdExecArgs (
        [
          "${pkgs.kiwix-tools}/bin/kiwix-serve"
          "--address"
          "ipv4"
          "--port"
          (toString port)
          "--skipInvalid"
        ]
        ++ zimFiles
      );
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
