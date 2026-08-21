{
  config,
  socMonitoring,
  ...
}:
let
  inherit (socMonitoring) seaweedfsS3;
in
{
  services.loki = {
    enable = true;
    # Lets the config reference the S3 credentials as ${ENV_VAR}
    # from the sops-templated EnvironmentFile below.
    extraFlags = [ "--config.expand-env=true" ];
    configuration = {
      auth_enabled = false;

      # No network client can reach Loki directly. nginx owns the
      # familiar :3100 port and proxies only explicitly allowed API
      # paths after client-certificate authorization.
      server = {
        http_listen_address = "127.0.0.1";
        http_listen_port = 3101;
        grpc_listen_address = "127.0.0.1";
      };

      common = {
        # In single-binary mode the query frontend advertises this
        # address to the colocated querier. Keep it aligned with the
        # loopback-only gRPC listener above; otherwise queries are
        # sent to 172.16.25.51:9095 and fail with connection refused.
        instance_addr = "127.0.0.1";
        path_prefix = "/var/lib/loki";
        replication_factor = 1;
        ring = {
          instance_addr = "127.0.0.1";
          kvstore.store = "inmemory";
        };
        storage.s3 = {
          endpoint = seaweedfsS3;
          bucketnames = "loki";
          region = "us-east-1";
          access_key_id = "\${LOKI_S3_ACCESS_KEY_ID}";
          secret_access_key = "\${LOKI_S3_SECRET_ACCESS_KEY}";
          # HTTPS with a ThornCloud_CA cert (trusted via
          # security.pki below). SeaweedFS doesn't do virtual-hosted
          # bucket addressing.
          s3forcepathstyle = true;
        };
      };

      schema_config.configs = [
        {
          from = "2026-01-01";
          store = "tsdb";
          object_store = "s3";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }
      ];

      storage_config.tsdb_shipper = {
        active_index_directory = "/var/lib/loki/tsdb-index";
        cache_location = "/var/lib/loki/tsdb-cache";
      };

      compactor = {
        working_directory = "/var/lib/loki/compactor";
        retention_enabled = true;
        delete_request_store = "s3";
      };

      limits_config = {
        # GeoIP values are intentionally structured metadata instead
        # of indexed labels. Schema v13 above stores that metadata in
        # chunk format v4 without exploding stream cardinality.
        allow_structured_metadata = true;
        retention_period = "90d";
        reject_old_samples = true;
        reject_old_samples_max_age = "168h";
      };
    };
  };
  systemd.services.loki.serviceConfig.EnvironmentFile = config.sops.templates."loki-s3.env".path;
}
