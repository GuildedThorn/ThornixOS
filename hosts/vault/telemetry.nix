# Vault's deployed SSH host key is enrolled in .sops.yaml and the shared
# telemetry secret, keeping telemetry activation atomic with SOC readiness.
{ ... }:
{
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;
}
