{ ... }:
{
  nixos.modules.services-mongodb =
    {
      config,
      ...
    }:
    {
      assertions = [
        {
          assertion = config.networking.hostName == "granite";
          message = "services-mongodb is currently intended for the granite host";
        }
      ];

      virtualisation.podman.enable = true;
      virtualisation.oci-containers.backend = "podman";
      virtualisation.oci-containers.containers.mongodb = {
        image = "docker.io/library/mongo:8.3.9";
        user = "568:568";
        ports = [ "172.16.25.4:27017:27017" ];
        volumes = [
          "/.ix-apps/app_mounts/mongodb/data:/data/db"
        ];
        environmentFiles = [ "/etc/mongodb.env" ];
        cmd = [
          "--bind_ip_all"
          "--auth"
        ];
      };

      # The bind-mounted data directory arrived from TrueNAS owned by root, but
      # mongod runs as 568:568 inside the container and must create its journal
      # subdirectory. `d` covers a fresh deploy; `Z` repairs the migrated tree.
      systemd.tmpfiles.rules = [
        "d /.ix-apps/app_mounts/mongodb/data 0750 568 568 -"
        "Z /.ix-apps/app_mounts/mongodb/data 0750 568 568 -"
      ];

      networking.firewall.allowedTCPPorts = [ 27017 ];
    };
}
