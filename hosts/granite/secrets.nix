{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Jellyfin API key used by MusicGrabber to trigger a library rescan after
  # downloads. Store the bare key; the template wraps it in the env-file form
  # the container reads.
  sops.secrets.jellyfin_api_key.restartUnits = [ "podman-musicgrabber.service" ];
  sops.templates."musicgrabber.env".content = ''
    JELLYFIN_API_KEY=${config.sops.placeholder.jellyfin_api_key}
  '';
}
