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
        cmd = [ "--bind_ip_all" "--auth" ];
      };

      networking.firewall.allowedTCPPorts = [ 27017 ];
    };
}
