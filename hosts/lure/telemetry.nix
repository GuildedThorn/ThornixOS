# Lure's SSH-derived age recipient is present in .sops.yaml and the shared
# telemetry secret. Keeping enrollment as a separate host file makes rotation
# explicit and lets the computer and SOC configurations change atomically.
{ ... }:
{
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;
}
