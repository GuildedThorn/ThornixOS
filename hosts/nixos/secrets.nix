{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;

  sops.secrets.wakatime_api_key = { };

  # Gmail app passwords - consumed automatically via passwordCommand/pass_cmd
  # by neomutt+mbsync+msmtp (hosts/nixos/home.nix mkGmailAccount) and by
  # matcha (modules/home-manager/matcha.nix), both of which read these
  # straight off disk. No manual re-entry needed.
  sops.secrets.gmail_guildedthorn_app_password.owner = "thorn";
  sops.secrets.gmail_opticalpvpx_app_password.owner = "thorn";
  sops.secrets.gmail_jamieduddleston2_app_password.owner = "thorn";

  # WeeChat CertFP client certs: one PEM per network with the client cert
  # and private key concatenated. WeeChat reads these straight off disk,
  # so no manual re-entry needed - just register the fingerprint once with
  # NickServ after rebuild (`/msg NickServ CERT ADD`, once connected with
  # the cert loaded).
  sops.secrets.oftc_client_cert.owner = "thorn";

  # Read-only mTLS identity for the CRT's direct Loki/Prometheus queries.
  # The matching public certificate lives in certs/; nginx on soc grants
  # this CN query endpoints only (never push, remote-write, or admin APIs).
  sops.secrets.telemetry_reader_key = {
    owner = "thorn";
  };

  sops.templates."wakatime.cfg" = {
    content = ''
      [settings]
      api_key = ${config.sops.placeholder.wakatime_api_key}
      api_url = https://wakapi.dev/api
    '';
    path = "/home/thorn/.wakatime.cfg";
    owner = "thorn";
  };
}
