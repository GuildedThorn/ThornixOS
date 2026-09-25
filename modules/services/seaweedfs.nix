{ ... }:
{
  nixos.modules.services-seaweedfs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      dataRoot = "/.ix-apps/app_mounts/seaweedfs";
      weed = "${pkgs.seaweedfs}/bin/weed";
      master = "127.0.0.1:30301.30371";
      filer = "127.0.0.1:30303.30372";
      common = {
        User = "seaweedfs";
        Group = "seaweedfs";
        Restart = "on-failure";
        RestartSec = 5;
        LimitNOFILE = 1048576;
        RequiresMountsFor = [ dataRoot ];
      };
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "granite";
          message = "services-seaweedfs is currently intended for the granite host";
        }
      ];

      users.groups.seaweedfs.gid = 568;
      users.users.seaweedfs = {
        uid = 568;
        group = "seaweedfs";
        isSystemUser = true;
      };

      systemd.services = {
        seaweedfs-master = {
          description = "SeaweedFS master";
          wantedBy = [ "multi-user.target" ];
          after = [ "zfs-mount.service" ];
          serviceConfig = common // {
            ExecStart = lib.concatStringsSep " " [
              weed
              "-logtostderr=true"
              "master"
              "-ip=127.0.0.1"
              "-ip.bind=127.0.0.1"
              "-port=30301"
              "-port.grpc=30371"
              "-mdir=${dataRoot}/master-data/m30301"
              "-volumeSizeLimitMB=30000"
            ];
          };
        };

        seaweedfs-volume = {
          description = "SeaweedFS volume server";
          wantedBy = [ "multi-user.target" ];
          after = [ "seaweedfs-master.service" ];
          requires = [ "seaweedfs-master.service" ];
          serviceConfig = common // {
            ExecStart = lib.concatStringsSep " " [
              weed
              "-logtostderr=true"
              "volume"
              "-master=${master}"
              "-ip=127.0.0.1"
              "-ip.bind=0.0.0.0"
              "-port=30302"
              "-port.grpc=30374"
              "-dir=${dataRoot}/volume-data"
              "-max=0"
              "-rack=Office Rack"
              "-dataCenter=ThornCloud"
            ];
          };
        };

        seaweedfs-filer = {
          description = "SeaweedFS filer";
          wantedBy = [ "multi-user.target" ];
          after = [ "seaweedfs-master.service" ];
          requires = [ "seaweedfs-master.service" ];
          serviceConfig = common // {
            ExecStart = lib.concatStringsSep " " [
              weed
              "-logtostderr=true"
              "filer"
              "-master=${master}"
              "-ip=127.0.0.1"
              "-ip.bind=0.0.0.0"
              "-port=30303"
              "-port.grpc=30372"
              "-defaultStoreDir=${dataRoot}/filer-data"
            ];
          };
        };

        seaweedfs-s3 = {
          description = "SeaweedFS S3 gateway";
          wantedBy = [ "multi-user.target" ];
          after = [ "seaweedfs-filer.service" "seaweedfs-volume.service" ];
          requires = [ "seaweedfs-filer.service" "seaweedfs-volume.service" ];
          serviceConfig = common // {
            ExecStart = lib.concatStringsSep " " [
              weed
              "-logtostderr=true"
              "s3"
              "-filer=${filer}"
              "-ip.bind=127.0.0.1"
              "-port=30305"
              "-port.grpc=30375"
              "-externalUrl=https://truenas.guildedthorn.arpa:30304"
            ];
          };
        };

        seaweedfs-admin = {
          description = "SeaweedFS admin";
          wantedBy = [ "multi-user.target" ];
          after = [ "seaweedfs-master.service" "seaweedfs-filer.service" "seaweedfs-volume.service" ];
          requires = [ "seaweedfs-master.service" "seaweedfs-filer.service" "seaweedfs-volume.service" ];
          serviceConfig = common // {
            ExecStart = lib.concatStringsSep " " [
              weed
              "-logtostderr=true"
              "admin"
              "-master=${master}"
              "-dataDir=${dataRoot}/admin-data"
              "-port=30300"
              "-port.grpc=30370"
            ];
          };
        };

        seaweedfs-worker = {
          description = "SeaweedFS maintenance worker";
          wantedBy = [ "multi-user.target" ];
          after = [ "seaweedfs-admin.service" ];
          requires = [ "seaweedfs-admin.service" ];
          serviceConfig = common // {
            ExecStart = lib.concatStringsSep " " [
              weed
              "-logtostderr=true"
              "worker"
              "-workingDir=${dataRoot}/worker-data"
              "-metricsPort=30368"
              "-admin=127.0.0.1:30300.30370"
            ];
          };
        };
      };

      services.nginx = {
        enable = true;
        virtualHosts."seaweedfs-s3" = {
          serverName = "truenas.guildedthorn.arpa";
          onlySSL = true;
          sslCertificate = "/var/lib/acme/forgejo.guildedthorn.arpa/fullchain.pem";
          sslCertificateKey = "/var/lib/acme/forgejo.guildedthorn.arpa/key.pem";
          sslTrustedCertificate = "/var/lib/acme/forgejo.guildedthorn.arpa/chain.pem";
          listen = [
            {
              addr = "0.0.0.0";
              port = 30304;
              ssl = true;
            }
          ];
          extraConfig = ''
            client_max_body_size 0;
            proxy_request_buffering off;
            proxy_buffering off;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:30305";
            proxyWebsockets = true;
          };
        };
      };

      networking.firewall.allowedTCPPorts = [ 30304 ];
    };
}
