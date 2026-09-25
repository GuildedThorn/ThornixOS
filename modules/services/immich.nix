{ ... }:
{
  nixos.modules.services-immich =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "immich.guildedthorn.arpa";
      dataRoot = "/.ix-apps/app_mounts/immich";
      uploadRoot = "${dataRoot}/data";
      databaseRoot = "${dataRoot}/postgres_data/18/docker";
      datasets = [
        "platter/ix-apps/app_mounts/immich"
        "platter/ix-apps/app_mounts/immich/data"
        "platter/ix-apps/app_mounts/immich/postgres_data"
      ];
      zfs = "/run/current-system/sw/bin/zfs";
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "granite";
          message = "services-immich is currently intended for the granite host";
        }
      ];

      virtualisation.podman.enable = true;
      virtualisation.oci-containers.backend = "podman";

      # These datasets were created by TrueNAS with canmount=noauto. Mount them
      # explicitly before any container starts; this avoids a missing ZFS mount
      # becoming an empty directory on the boot disk.
      systemd.services = {
        immich-datasets = {
        description = "Mount preserved Immich ZFS datasets";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import-platter.service" "zfs-mount.service" ];
        before = [
          "podman-immich-postgres.service"
          "podman-immich-redis.service"
          "podman-immich-server.service"
          "podman-immich-machine-learning.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = let
            mountCommands = lib.concatStringsSep " && " (
              map (dataset: "${zfs} mount ${lib.escapeShellArg dataset} 2>/dev/null || test \"$(${zfs} get -H -o value mounted ${lib.escapeShellArg dataset})\" = yes") datasets
            );
          in "${pkgs.bash}/bin/bash -c ${lib.escapeShellArg mountCommands}";
        };
        };
      } // lib.genAttrs [
        "podman-immich-postgres"
        "podman-immich-redis"
        "podman-immich-server"
        "podman-immich-machine-learning"
      ] (_: {
        after = [ "immich-datasets.service" ];
        requires = [ "immich-datasets.service" ];
      });

      systemd.tmpfiles.rules = [
        "d /var/lib/immich 0750 root root -"
        "d /var/lib/immich/redis 0750 568 568 -"
        "d /var/lib/immich/model-cache 0750 568 568 -"
      ];

      virtualisation.oci-containers.containers = {
        immich-postgres = {
          image = "ghcr.io/immich-app/postgres:18-vectorchord0.5.3";
          environmentFiles = [ "/etc/immich.env" ];
          environment = {
            POSTGRES_INITDB_ARGS = "--data-checksums";
            PGDATA = "/var/lib/postgresql/data";
          };
          volumes = [ "${databaseRoot}:/var/lib/postgresql/data" ];
          extraOptions = [ "--shm-size=128m" "--network=host" ];
        };

        immich-redis = {
          image = "docker.io/valkey/valkey:9";
          volumes = [ "/var/lib/immich/redis:/data" ];
          extraOptions = [ "--network=host" ];
        };

        immich-server = {
          image = "ghcr.io/immich-app/immich-server:v3.1.0";
          environmentFiles = [ "/etc/immich.env" ];
          environment = {
            DB_HOSTNAME = "127.0.0.1";
            DB_PORT = "5432";
            REDIS_HOSTNAME = "127.0.0.1";
            MACHINE_LEARNING_URL = "http://127.0.0.1:3003";
            IMMICH_PORT = "2283";
            TZ = "America/Chicago";
          };
          volumes = [
            "${uploadRoot}:/data"
            "/etc/localtime:/etc/localtime:ro"
          ];
          extraOptions = [ "--network=host" ];
          dependsOn = [ "immich-postgres" "immich-redis" ];
        };

        immich-machine-learning = {
          image = "ghcr.io/immich-app/immich-machine-learning:v3.1.0";
          environmentFiles = [ "/etc/immich.env" ];
          environment = {
            TZ = "America/Chicago";
          };
          volumes = [ "/var/lib/immich/model-cache:/cache" ];
          extraOptions = [ "--network=host" ];
        };
      };

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        virtualHosts.${hostname} = {
          serverName = hostname;
          forceSSL = true;
          useACMEHost = "forgejo.guildedthorn.arpa";
          extraConfig = ''
            add_header Strict-Transport-Security "max-age=31536000" always;
            add_header X-Content-Type-Options "nosniff" always;
            client_max_body_size 50000m;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:2283";
            proxyWebsockets = true;
          };
        };
      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];
    };
}
