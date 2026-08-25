{ ... }:
{
  # Loom's SSH host key is enrolled in the shared telemetry secret so Alloy
  # can authenticate to the SOC without putting a private key in the store.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;
}
