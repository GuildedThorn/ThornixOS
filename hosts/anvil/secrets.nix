{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;

  sops.secrets.step_ca_intermediate_key = {
    owner = "step-ca";
    group = "step-ca";
    mode = "0400";
    restartUnits = [ "step-ca.service" ];
  };

  # PID 1 reads this root-owned file into a private systemd credential. It is
  # never placed in ca.json, an environment variable, or the Nix store.
  sops.secrets.step_ca_intermediate_password = {
    mode = "0400";
    restartUnits = [ "step-ca.service" ];
  };
}
