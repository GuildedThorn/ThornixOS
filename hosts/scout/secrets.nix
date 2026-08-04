{ ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;

  # WireGuard road-warrior credentials (see ./wireguard.nix). Both are read
  # from files by wg-quick, so they never enter the Nix store.
  sops.secrets.wg_private_key = { };
  sops.secrets.wg_preshared_key = { };
}
