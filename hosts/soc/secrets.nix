{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;

  # Grafana and nginx share the SOC server certificate. Keep its private key
  # root-owned and grant only those two services read access through a
  # dedicated supplementary group.
  users.groups.telemetry-tls = { };

  # Outbound dead-man heartbeat. The URL contains the check UUID, so keep it
  # out of the Nix store and expose it only to the root-owned oneshot service.
  sops.secrets.healthchecks_ping_url = { };
  sops.templates."healthchecks.env".content = ''
    HEALTHCHECKS_URL=${config.sops.placeholder.healthchecks_ping_url}
  '';

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

  # restic repository password for the Prometheus TSDB backup. NOT
  # recoverable — if this is lost the repo is unreadable, so it wants to be
  # somewhere outside this fleet as well (password manager), not only here.
  #
  # ACTION REQUIRED before soc next deploys: this secret must exist in
  # secrets.yaml or the restic units fail (the rest of soc still comes up).
  #   sops hosts/soc/secrets.yaml   → add `restic_password: <long random>`
  sops.secrets.restic_password = { };

  # S3 credentials for the restic repo. Deliberately reusing the loki
  # keypair rather than minting a second one: same NAS, same trust
  # boundary, and it keeps this to a single new secret to provision. If you
  # ever want least-privilege per-bucket creds, add
  # restic_s3_{access_key_id,secret_access_key} and swap them in here.
  sops.templates."restic-s3.env" = {
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.loki_s3_access_key_id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.loki_s3_secret_access_key}
    '';
  };

  sops.secrets.grafana_admin_password.owner = "grafana";
  # Grafana encrypts DB secrets with this; it has no default anymore and
  # can't be rotated easily — generated once, never needs manual editing.
  sops.secrets.grafana_secret_key.owner = "grafana";

  # Discord webhook the SIEM alert rules notify. Read into the provisioned
  # contact point via $__file{} so the URL never lands in the Nix store.
  sops.secrets.grafana_discord_webhook.owner = "grafana";

  # TLS private key for Grafana's HTTPS listener. The matching cert
  # (ThornCloud_CA-signed) lives in the repo at certs/; only the key is
  # secret. Add the PEM to secrets.yaml before deploying the https block.
  sops.secrets.grafana_tls_key = {
    owner = "root";
    group = "telemetry-tls";
    mode = "0440";
    restartUnits = [
      "grafana.service"
      "nginx.service"
    ];
  };
  systemd.services.grafana.serviceConfig.SupplementaryGroups = [ "telemetry-tls" ];
  systemd.services.nginx.serviceConfig.SupplementaryGroups = [ "telemetry-tls" ];
}
