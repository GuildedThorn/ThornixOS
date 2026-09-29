{
  nixos.modules.services-hashtopolis-server =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.hashtopolisServer;

      stateDirectory = "/var/lib/hashtopolis";

      # Agents and the web UI are both served from this one origin. Keeping the
      # SPA and the API on the same scheme/host/port means the browser never
      # makes a cross-origin call to the backend, so the deployment does not
      # depend on the backend shipping permissive CORS headers, and the admin
      # session cookie is never sent in the clear.
      publicUrl = "https://${cfg.domain}";

      # The legacy agent protocol. The official Python agent POSTs its whole
      # request to whatever `url` it is given, so this must be the full
      # endpoint rather than the /api/v2 base the web UI uses.
      agentApiPath = "/api/server.php";

      # Only ever reachable through the nginx vhost above, which is restricted
      # to these networks. The published container ports themselves are bound
      # to loopback, so the NixOS firewall needs no new rules.
      #
      # nginx's `extraConfig` is typed as "strings concatenated with \n", so it
      # takes one newline-joined string, not a list of lines.
      allowDeny = lib.concatStringsSep "\n" (
        lib.map (network: "allow ${network};") cfg.allowedNetworks ++ [ "deny all;" ]
      );
    in
    {
      options.thorn.hashtopolisServer = {
        enable = lib.mkEnableOption "the Hashtopolis server";

        domain = lib.mkOption {
          type = lib.types.str;
          default = "hashtopolis.guildedthorn.arpa";
          description = ''
            Hostname the server is published under. Must be present in the
            host's ACME `extraDomainNames` so nginx can obtain a certificate
            for it.
          '';
        };

        acmeHost = lib.mkOption {
          type = lib.types.str;
          default = "mitm.guildedthorn.arpa";
          description = ''
            Existing ACME-enabled vhost whose certificate is reused, rather
            than requesting a separate certificate per service.
          '';
        };

        backendPort = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = ''
            Loopback port the PHP backend is published on. Matches the port
            upstream's own compose file uses.
          '';
        };

        frontendPort = lib.mkOption {
          type = lib.types.port;
          default = 4200;
          description = "Loopback port the Angular frontend is published on.";
        };

        allowedNetworks = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "127.0.0.1"
            "::1"
            "192.168.1.0/24"
            "172.16.25.0/24"
            "10.10.10.0/24"
          ];
          description = ''
            Networks permitted to reach the web UI and the agent API. This is
            a service that hands out administrator sessions and stores hash
            lists, so it is not published to the lab at large.
          '';
        };

        dbHost = lib.mkOption {
          type = lib.types.str;
          description = ''
            Address the backend container uses to reach the database.

            Podman's `podman` bridge has no embedded DNS on NixOS: aardvark-dns
            is absent from podman's closure, the network reports
            `dns_enabled: false`, and containers inherit the host's resolvers,
            so a container name never resolves. The database therefore runs
            with host networking and is addressed by IP.

            Use an address the backend can route to from the podman bridge -
            either this host's own address or the bridge gateway. The default
            podman subnet is 10.88.0.0/16.
          '';
        };

        sopsFile = lib.mkOption {
          type = lib.types.path;
          description = ''
            SOPS file holding the MySQL root password, the application
            database password, and the initial administrator password. It must
            be encrypted to the host's SSH-derived age recipient.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = builtins.pathExists cfg.sopsFile;
            message = "The Hashtopolis server SOPS file does not exist";
          }
        ];

        # Database state and the uploaded hashlists/cracker binaries. The
        # backend container writes its own share here, so it stays unencrypted
        # on disk under the podman service account like the rest of this
        # host's container state.
        systemd.tmpfiles.rules = [
          "d ${stateDirectory} 0750 root root -"
          "d ${stateDirectory}/mysql 0700 root root -"
          # This is the container's /usr/local/share/hashtopolis. The app runs
          # as www-data (uid 33) and must traverse into it to read config.json,
          # which holds the JWT peppers - without execute permission on this
          # directory StartupConfig silently loads an empty pepper and every
          # login fails with "Key material must not be empty". 0750 root root
          # here reproduces exactly that, so the group is opened up to the
          # container's service account. The dir itself holds no secrets; the
          # peppers inside are 0644 and only the DB datadir is kept private.
          "d ${stateDirectory}/hashtopolis 0755 root root -"
        ];

        sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

        sops.secrets = {
          hashtopolis_db_password = {
            sopsFile = cfg.sopsFile;
            restartUnits = [
              "podman-hashtopolis-db.service"
              "podman-hashtopolis-backend.service"
            ];
          };
          hashtopolis_db_root_password = {
            sopsFile = cfg.sopsFile;
            restartUnits = [ "podman-hashtopolis-db.service" ];
          };
          hashtopolis_admin_password = {
            sopsFile = cfg.sopsFile;
            restartUnits = [ "podman-hashtopolis-backend.service" ];
          };
        };

        # The MySQL image and the Hashtopolis backend name the same credential
        # differently, so each container gets its own env file rather than one
        # file carrying both spellings of the same secret.
        sops.templates."hashtopolis-db.env".content = ''
          MYSQL_ROOT_PASSWORD=${config.sops.placeholder.hashtopolis_db_root_password}
          MYSQL_DATABASE=hashtopolis
          MYSQL_USER=hashtopolis
          MYSQL_PASSWORD=${config.sops.placeholder.hashtopolis_db_password}
        '';

        sops.templates."hashtopolis-backend.env" = {
          owner = "root";
          mode = "0400";
          content = ''
            HASHTOPOLIS_ADMIN_USER=admin
            HASHTOPOLIS_ADMIN_PASSWORD=${config.sops.placeholder.hashtopolis_admin_password}
            HASHTOPOLIS_DB_USER=hashtopolis
            HASHTOPOLIS_DB_PASS=${config.sops.placeholder.hashtopolis_db_password}
          '';
        };

        virtualisation.podman.enable = true;
        virtualisation.oci-containers.backend = "podman";

        virtualisation.oci-containers.containers = {
          hashtopolis-db = {
            image = "docker.io/library/mysql:9.7";
            environmentFiles = [
              config.sops.templates."hashtopolis-db.env".path
            ];
            volumes = [ "${stateDirectory}/mysql:/var/lib/mysql" ];
            extraOptions = [
              # See `dbHost`: container-name DNS is unavailable, so the
              # datastore shares the host's network namespace and the backend
              # reaches it by address. mysqld listens on 0.0.0.0:3306, which
              # mitm's default-deny firewall keeps off the network - the same
              # exposure immich's postgres has on granite.
              "--network=host"
              "--memory=1g"
              "--memory-swap=1g"
            ];
          };

          hashtopolis-backend = {
            image = "docker.io/hashtopolis/backend:v1.0.1";
            environmentFiles = [
              config.sops.templates."hashtopolis-backend.env".path
            ];
            environment = {
              HASHTOPOLIS_DB_TYPE = "mysql";
              HASHTOPOLIS_DB_HOST = cfg.dbHost;
              HASHTOPOLIS_DB_DATABASE = "hashtopolis";
              HASHTOPOLIS_BACKEND_URL = "${publicUrl}/api/v2";
              # nginx terminates TLS on the shared service name, so the port
              # the backend embeds in generated frontend links is 443, not the
              # loopback port the container is published on.
              HASHTOPOLIS_FRONTEND_PORT = "443";
            };
            volumes = [ "${stateDirectory}/hashtopolis:/usr/local/share/hashtopolis" ];
            ports = [ "127.0.0.1:${toString cfg.backendPort}:80" ];
            # The image declares `User=www-data` but its Apache listens on the
            # privileged port 80, which a non-root process cannot bind - the
            # container dies with "AH00072: make_sock: could not bind to
            # address [::]:80" and never starts PHP. Ambient capabilities
            # cannot be granted for a non-root uid through the podman CLI, so
            # run the container as root and let the image drop privileges
            # itself. The frontend image declares no user and is unaffected.
            user = "0:0";
            dependsOn = [ "hashtopolis-db" ];
          };

          hashtopolis-frontend = {
            image = "docker.io/hashtopolis/frontend:v1.0.1";
            environment = {
              HASHTOPOLIS_BACKEND_URL = "${publicUrl}/api/v2";
            };
            ports = [ "127.0.0.1:${toString cfg.frontendPort}:80" ];
            # Container attribute names, not the generated podman-*.service
            # unit names: `dependsOn` is resolved against `containers`.
            dependsOn = [ "hashtopolis-backend" ];
          };
        };

        # The database runs with host networking (see `dbHost`), so the
        # backend reaches it by addressing this host across the podman bridge.
        # mitm's firewall is default-deny, and 3306 is not an allowed service,
        # so without this the connection is silently dropped and the backend
        # blocks in its entrypoint waiting on the database - it looks like a
        # hang rather than a refusal. Scoping the exception to podman0 keeps
        # mysqld unreachable from the network.
        networking.firewall.extraCommands = ''
          iptables -w -A nixos-fw -i podman0 -p tcp --dport 3306 -j nixos-fw-accept
        '';

        services.nginx.virtualHosts.${cfg.domain} = {
          serverName = cfg.domain;
          forceSSL = true;
          useACMEHost = cfg.acmeHost;

          # The agent protocol lives under /api/ alongside the v2 REST API, so
          # a single prefix covers both the browser and every agent.
          locations."/api/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.backendPort}";
            extraConfig = allowDeny;
          };

          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.frontendPort}";
            proxyWebsockets = true;
            extraConfig = allowDeny;
          };
        };
      };
    };
}
