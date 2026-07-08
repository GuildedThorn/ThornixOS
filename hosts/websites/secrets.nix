{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # The app's whole dotenv as one opaque secret (Jwt__Key,
  # MongoDB__ConnectionString, RabbitMQ__Password, Spotify__ClientSecret, ...).
  # Edit with `sops hosts/websites/secrets.yaml` and paste the contents of the
  # previous /etc/guildedthorn/secrets.env verbatim.
  sops.secrets.guildedthorn_env = { };

  # Cloudflare tunnel token: store the bare token; the template wraps it in
  # the TUNNEL_TOKEN= form cloudflared expects from its EnvironmentFile.
  sops.secrets.cloudflared_tunnel_token = { };
  sops.templates."cloudflared.env".content = ''
    TUNNEL_TOKEN=${config.sops.placeholder.cloudflared_tunnel_token}
  '';
}
