{
  nixos.modules.mc-cluster =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.mc-cluster;

      # Pinned Agones Helm chart. Rendered at install time by helm on the box
      # itself (upgrade --install runs the chart's lifecycle hooks, which
      # emit the --include-crds CRDs and wire the controller's mutating
      # webhook TLS).
      agonesChart = pkgs.fetchurl {
        url = "https://agones.dev/chart/stable/agones-${cfg.agones.version}.tgz";
        sha256 = cfg.agones.chartSha256;
      };

      waitForK3s = pkgs.writeShellScript "wait-for-k3s" ''
        set -euo pipefail
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        until ${pkgs.kubectl}/bin/kubectl get namespace default >/dev/null 2>&1; do
          sleep 3
        done
      '';

      installAgones = pkgs.writeShellScript "install-agones" ''
        set -euo pipefail
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        ${pkgs.kubernetes-helm}/bin/helm upgrade --install agones ${agonesChart} \
          --namespace agones-system --create-namespace \
          --wait --atomic --timeout 10m
        ${pkgs.kubectl}/bin/kubectl --namespace agones-system \
          rollout status deployment/agones-controller --timeout=300s
      '';
    in
    {
      options.thorn.mc-cluster = {
        enable = lib.mkEnableOption "k3s + Agones Minecraft cluster node";

        environment = lib.mkOption {
          type = lib.types.enum [
            "dev"
            "prod"
          ];
          default = "dev";
          description = "Deployment environment; gates registries, tags, and resource budgets.";
        };

        registry = lib.mkOption {
          type = lib.types.str;
          default = "ghcr.io/guildedthorn";
          description = "Container registry carrying minecraft server images.";
        };

        k3s = {
          role = lib.mkOption {
            type = lib.types.enum [
              "server"
              "agent"
            ];
            default = "server";
          };

          serverAddr = lib.mkOption {
            type = lib.types.str;
            default = "https://127.0.0.1:6443";
            description = "k3s API address; agents override with the server node.";
          };

          token = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "k3s join token; sops-backed for agents, empty for the first server.";
          };

          nodeIp = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Kubelet-advertised node IP (the host's LAN address).";
          };

          extraFlags = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "--disable=traefik" ];
          };
        };

        agones = {
          version = lib.mkOption {
            type = lib.types.str;
            default = "1.61.0";
          };

          chartSha256 = lib.mkOption {
            type = lib.types.str;
            default = "4d0655f27fb5cb8a619b54bbae2ab0ca826227759c82f5641cd503dfd2721125";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.k3s = {
          enable = true;
          role = cfg.k3s.role;
          token = cfg.k3s.token;
          serverAddr = cfg.k3s.serverAddr;
          extraFlags =
            cfg.k3s.extraFlags ++ lib.optional (cfg.k3s.nodeIp != null) "--node-ip=${cfg.k3s.nodeIp}";
        };

        assertions = [
          {
            assertion =
              cfg.k3s.role == "server" || (cfg.k3s.token != "" && cfg.k3s.serverAddr != "https://127.0.0.1:6443");
            message = ''
              mc-cluster: an agent node requires a join token (k3s.token) and the
              real API address of the server node (k3s.serverAddr).
            '';
          }
        ];

        systemd.services.mc-agones-install = lib.mkIf (cfg.k3s.role == "server") {
          description = "Install pinned Agones controller and allocator into the k3s cluster";
          after = [ "k3s.service" ];
          requires = [ "k3s.service" ];
          wantedBy = [ "multi-user.target" ];
          path = [
            pkgs.kubectl
            pkgs.kubernetes-helm
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "15m";
            ExecStartPre = "${waitForK3s}";
            ExecStart = "${installAgones}";
          };
        };

        environment.systemPackages = [
          pkgs.kubectl
          pkgs.kubernetes-helm
        ];
      };
    };
}
