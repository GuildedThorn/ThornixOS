{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # SeaweedFS S3 credentials for the `loki` bucket, exposed to Loki as an
  # EnvironmentFile so the config can use ${...} via --config.expand-env.
  sops.secrets.loki_s3_access_key_id = { };
  sops.secrets.loki_s3_secret_access_key = { };
  sops.templates."loki-s3.env" = {
    owner = "loki";
    content = ''
      LOKI_S3_ACCESS_KEY_ID=${config.sops.placeholder.loki_s3_access_key_id}
      LOKI_S3_SECRET_ACCESS_KEY=${config.sops.placeholder.loki_s3_secret_access_key}
    '';
  };

  sops.secrets.grafana_admin_password.owner = "grafana";
  # Grafana encrypts DB secrets with this; it has no default anymore and
  # can't be rotated easily — generated once, never needs manual editing.
  sops.secrets.grafana_secret_key.owner = "grafana";

  # Discord webhook the SIEM alert rules notify. Read into the provisioned
  # contact point via $__file{} so the URL never lands in the Nix store.
  sops.secrets.grafana_discord_webhook.owner = "grafana";
}
