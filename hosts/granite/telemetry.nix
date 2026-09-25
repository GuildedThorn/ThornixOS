{ ... }:
{
  # Enroll Granite in the existing SOC Alloy -> Loki and node_exporter path.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;
}
