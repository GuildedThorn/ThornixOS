{ ... }:
{
  # Required for the vmbr1 Zeek sensor's Alloy config to be consumed; without
  # it the lab's conn/DNS/HTTP/TLS logs are written locally and never shipped.
  thorn.telemetry.enable = true;

  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
}
