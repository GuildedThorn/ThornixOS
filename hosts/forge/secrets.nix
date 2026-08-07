{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets = {
    cachix_auth_token = {
      mode = "0400";
      restartUnits = [
        "cachix-watch-store-agent.service"
        "thornix-promote-production.service"
      ];
    };
    github_deploy_key = {
      mode = "0400";
      restartUnits = [ "thornix-promote-production.service" ];
    };
  };

  thorn.forgePromotion = {
    enable = true;
    cachixTokenFile = config.sops.secrets.cachix_auth_token.path;
    githubDeployKeyFile = config.sops.secrets.github_deploy_key.path;
  };
}
