{
  nixos.modules.mc-lobby =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.mc-lobby;
      k3s = config.thorn.mc-cluster.k3s;
      clusterEnabled = config.thorn.mc-cluster.enable or false;

      # Pure builders live under lib/mc/ (outside modules/, which import-tree
      # would otherwise load as flake-parts modules). Each takes explicit
      # arguments so the module body stays options + wiring only.
      configs = import ../../lib/mc/configs.nix { inherit lib cfg; };
      entrypoints = import ../../lib/mc/entrypoints.nix { inherit pkgs cfg; };
      images = import ../../lib/mc/images.nix {
        inherit
          pkgs
          cfg
          configs
          entrypoints
          ;
      };
      manifests = import ../../lib/mc/manifests.nix {
        inherit pkgs cfg;
        inherit (images) lobbyTag proxyTag;
      };
      autoscalerPy = import ../../lib/mc/autoscaler.nix { inherit pkgs; };

      forwardingSecret = config.sops.secrets."minecraft/forwarding-secret".path;
      rconSecret = config.sops.secrets."minecraft/rcon-password".path;
    in
    {
      options.thorn.mc-lobby = {
        enable = lib.mkEnableOption "Minecraft lobby pool: Velocity proxy + fairscale Paper lobbies";

        environment = lib.mkOption {
          type = lib.types.enum [
            "dev"
            "prod"
          ];
          default = "dev";
        };

        domainSuffix = lib.mkOption {
          type = lib.types.str;
          default = "mc.theroux.local";
        };

        maxPlayersPerLobby = lib.mkOption {
          type = lib.types.int;
          default = 40;
        };

        maxLobbies = lib.mkOption {
          type = lib.types.int;
          default = 4;
        };

        lobbyPort = lib.mkOption {
          type = lib.types.port;
          default = 25565;
        };

        rconPort = lib.mkOption {
          type = lib.types.port;
          default = 25575;
        };

        identity = lib.mkOption {
          type = lib.types.str;
          default = "mc-lobby";
        };

        namespace = lib.mkOption {
          type = lib.types.str;
          default = "mc";
        };

        whitelist = lib.mkOption {
          description = ''
            Players allowed to join. Each entry needs the account name and its
            Mojang UUID (resolved online by the Velocity proxy). An empty list
            disables the whitelist.
          '';
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                uuid = lib.mkOption { type = lib.types.str; };
              };
            }
          );
          default = [ ];
        };

        ops = lib.mkOption {
          description = ''
            Operators (level 4), each with the account name and its Mojang UUID.
          '';
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                uuid = lib.mkOption { type = lib.types.str; };
              };
            }
          );
          default = [ ];
        };

        lobbyHeapGb = lib.mkOption {
          type = lib.types.int;
          default = 2;
        };

        proxyHeapGb = lib.mkOption {
          type = lib.types.int;
          default = 1;
        };

        autoscalerInterval = lib.mkOption {
          type = lib.types.int;
          default = 30;
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = clusterEnabled;
            message = "mc-lobby requires mc-cluster (k3s + Agones). Enable thorn.mc-cluster first.";
          }
        ];

        networking.firewall.allowedTCPPorts = [ cfg.lobbyPort ];

        # Velocity forwarding secret + RCON password, decrypted to
        # /run/secrets/minecraft/* by sops-nix. Keys are upper-case so the
        # resulting k8s Secret can be projected via envFrom without renaming.
        sops.secrets."minecraft/forwarding-secret" = {
          sopsFile = ../../hosts/shared/minecraft-secrets.yaml;
          key = "forwarding_secret";
          mode = "0400";
        };
        sops.secrets."minecraft/rcon-password" = {
          sopsFile = ../../hosts/shared/minecraft-secrets.yaml;
          key = "rcon_password";
          mode = "0400";
        };

        systemd.services.mc-lobby-install = lib.mkIf (k3s.role == "server") {
          description = "Apply Minecraft lobby pool to the k3s cluster";
          after = [ "mc-agones-install.service" ];
          requires = [ "mc-agones-install.service" ];
          before = [ "mc-lobby-autoscaler.service" ];
          path = [
            pkgs.kubectl
            pkgs.k3s
          ];
          environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "15m";
          };
          script = ''
            set -euo pipefail

            k3s ctr -n k8s.io images import ${images.lobbyImage}
            k3s ctr -n k8s.io images import ${images.proxyImage}

            kubectl apply -f ${manifests.namespace}
            kubectl create secret generic mc-secrets \
              -n ${cfg.namespace} \
              --from-file=FORWARDING_SECRET=${forwardingSecret} \
              --from-file=RCON_PASSWORD=${rconSecret} \
              --dry-run=client -o yaml | kubectl apply -f -
            kubectl apply -f ${manifests.lobby}
            kubectl apply -f ${manifests.lobbyService}
            kubectl apply -f ${manifests.velocity}
            kubectl apply -f ${manifests.velocityService}

            kubectl rollout status --timeout=600s deployment/${cfg.identity} -n ${cfg.namespace}
            kubectl rollout status --timeout=600s deployment/mc-velocity -n ${cfg.namespace}
          '';
        };

        systemd.services.mc-lobby-autoscaler = lib.mkIf (k3s.role == "server") {
          description = "Scale lobby pool to demand using RCON player counts";
          after = [ "mc-lobby-install.service" ];
          requires = [ "mc-lobby-install.service" ];
          wantedBy = [ "multi-user.target" ];
          restartIfChanged = true;
          environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
          path = [ pkgs.kubectl ];
          serviceConfig = {
            ExecStart = ''
              ${pkgs.python3}/bin/python3 -u ${autoscalerPy} \
                --interval ${toString cfg.autoscalerInterval} \
                --label app=${cfg.identity} \
                --deployment ${cfg.identity} \
                --namespace ${cfg.namespace} \
                --max-per-lobby ${toString cfg.maxPlayersPerLobby} \
                --max-lobbies ${toString cfg.maxLobbies} \
                --rcon-port ${toString cfg.rconPort} \
                --rcon-password-file ${rconSecret}
            '';
            Restart = "always";
            RestartSec = "10s";
          };
        };
      };
    };
}
