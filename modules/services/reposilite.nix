{ ... }:
{
  nixos.modules.services-reposilite =
    {
      config,
      lib,
      ...
    }:
    let
      hostname = "reposilite.guildedthorn.arpa";
      stateDir = "/platter/services/reposilite";
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "granite";
          message = "services-reposilite is currently intended for the granite host";
        }
      ];

      services.reposilite = {
        enable = true;
        # Maven / Gradle artifact storage; keeps the working directory on the
        # preserved platter dataset like the other granite services.
        workingDirectory = stateDir;
        openFirewall = false;
        settings = {
          hostname = "127.0.0.1";
          # qbittorrent already owns 8080 on this host.
          port = 8084;
          enforceSsl = false;
        };
      };

      # The upstream module only auto-creates the state directory when it lives
      # under /var/lib; /platter is a separate ZFS pool mounted later.
      systemd.tmpfiles.rules = [
        "d ${stateDir} 0750 reposilite reposilite -"
      ];

      # ProtectSystem=strict makes the whole filesystem read-only; the upstream
      # module only carves out a writable path when the state dir is under
      # /var/lib, so an out-of-tree working directory must be granted explicitly.
      systemd.services.reposilite.serviceConfig.ReadWritePaths = [ stateDir ];

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        virtualHosts.${hostname} = {
          serverName = hostname;
          forceSSL = true;
          # Certificate (from the ThornCloud step-ca ACME service) is issued to
          # forgejo and shared with the other granite services via an extra SAN.
          useACMEHost = "forgejo.guildedthorn.arpa";
          extraConfig = ''
            add_header Strict-Transport-Security "max-age=31536000" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "same-origin" always;
            client_max_body_size 500m;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:8084";
          };
        };
      };

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
    };
}
