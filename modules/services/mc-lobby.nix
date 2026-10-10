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

      # Content-addressed tags: a change to jars, JVM, JVM-less runtime deps,
      # baked config, or entrypoint logic yields a new tag, so `kubectl apply`
      # actually rolls pods instead of leaving the old image running under
      # IfNotPresent. `lobbyEntrypoint`/`proxyEntrypoint` are store paths whose
      # names hash their inputs, so they capture entrypoint and config changes.
      # Declarative whitelist, keyed by Mojang UUID: the Velocity proxy
      # authenticates players online, so the backend receives each player's
      # real account UUID rather than an offline-mode name derivation.
      whitelistJson = builtins.toJSON (map (p: { inherit (p) name uuid; }) cfg.whitelist);

      shortHash = s: builtins.substring 0 12 (builtins.hashString "sha256" s);
      lobbyTag = "${cfg.environment}-${
        shortHash (
          playerConfig
          + paperGlobalConfig
          + whitelistJson
          + toString lobbyEntrypoint
          + toString pkgs.coreutils
          + pkgs.jdk25.version
          + pkgs.papermc.version
        )
      }";
      proxyTag = "${cfg.environment}-${
        shortHash (
          proxyConfig
          + toString proxyEntrypoint
          + toString pkgs.coreutils
          + pkgs.jdk25.version
          + pkgs.velocity.version
        )
      }";

      # Jars are unpacked from nixpkgs to a stable layout so the image build
      # never depends on upstream output names.
      mcJars = pkgs.runCommand "mc-server-jars" { } ''
        mkdir -p $out
        cp ${pkgs.papermc}/share/papermc/papermc.jar $out/lobby.jar
        cp ${pkgs.velocity}/share/velocity/velocity.jar $out/velocity.jar
      '';

      playerConfig = ''
        eula=true
        level-type=flat
        motd=Thornix Lobby
        server-port=${toString cfg.lobbyPort}
        max-players=${toString (cfg.maxPlayersPerLobby * 2)}
        view-distance=6
        online-mode=false
        enable-rcon=true
        rcon.port=${toString cfg.rconPort}
        rcon.password=__RCON_PASSWORD__
        broadcast-rcon-to-ops=false
        white-list=${lib.boolToString (cfg.whitelist != [ ])}
        enforce-whitelist=${lib.boolToString (cfg.whitelist != [ ])}
      '';

      # Modern Paper (1.19+) reads Velocity forwarding from paper-global.yml,
      # not server.properties. `_version` must accompany a partial override.
      paperGlobalConfig = ''
        _version: 31
        proxies:
          velocity:
            enabled: true
            online-mode: true
            secret: __FORWARDING_SECRET__
      '';

      # Velocity 4.x config-version 2.9: player forwarding is a top-level mode
      # plus a separate forwarding.secret file (no [forwarding] section).
      proxyConfig = ''
        config-version = "2.9"
        bind = "0.0.0.0:${toString cfg.lobbyPort}"
        motd = "<#09add3>Thornix Network"
        player-info-forwarding-mode = "modern"
        forwarding-secret-file = "forwarding.secret"

        [servers]
        lobby = "mc-lobby.mc.svc.cluster.local:${toString cfg.lobbyPort}"

        try = ["lobby"]

        [forced-hosts]
        "lobby.${cfg.domainSuffix}" = ["lobby"]

        [query]
        enabled = false
      '';

      # Rendered at container start from the baked template + env-provided
      # secrets, so the forwarding secret and RCON password never land in the
      # image, the store, or git. Each is wrapped in a directory because
      # buildLayeredImage `contents` entries must be directory trees.
      lobbyEntrypoint = pkgs.runCommand "mc-lobby-entry" { } ''
        mkdir -p $out
        cp ${pkgs.writeScript "mc-lobby-entrypoint.sh" ''
          #!${pkgs.runtimeShell}
          set -euo pipefail
          : "''${FORWARDING_SECRET:?FORWARDING_SECRET is required}"
          : "''${RCON_PASSWORD:?RCON_PASSWORD is required}"
          ${pkgs.gnused}/bin/sed \
            -e "s|__RCON_PASSWORD__|''${RCON_PASSWORD}|g" \
            /opt/server.properties.tmpl > /data/server.properties
          mkdir -p /data/config
          ${pkgs.gnused}/bin/sed \
            -e "s|__FORWARDING_SECRET__|''${FORWARDING_SECRET}|g" \
            /opt/paper-global.yml.tmpl > /data/config/paper-global.yml
          echo "eula=true" > /data/eula.txt
          cp /opt/whitelist.json /data/whitelist.json
          exec ${pkgs.jdk25}/bin/java -Xms1G -Xmx${toString cfg.lobbyHeapGb}G -jar /lobby.jar nogui
        ''} $out/entrypoint.sh
        chmod +x $out/entrypoint.sh
      '';

      proxyEntrypoint = pkgs.runCommand "mc-velocity-entry" { } ''
        mkdir -p $out
        cp ${pkgs.writeScript "mc-velocity-entrypoint.sh" ''
          #!${pkgs.runtimeShell}
          set -euo pipefail
          : "''${FORWARDING_SECRET:?FORWARDING_SECRET is required}"
          printf '%s' "''${FORWARDING_SECRET}" > /data/forwarding.secret
          cp /opt/velocity.toml.tmpl /data/velocity.toml
          exec ${pkgs.jdk25}/bin/java -Xms512M -Xmx${toString cfg.proxyHeapGb}G -jar /velocity.jar
        ''} $out/entrypoint.sh
        chmod +x $out/entrypoint.sh
      '';

      lobbyImage = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/guildedthorn/mc-lobby";
        tag = lobbyTag;
        contents = [
          pkgs.coreutils
          pkgs.jdk25
          pkgs.gnused
          mcJars
          lobbyEntrypoint
        ];
        extraCommands = ''
          mkdir -p ./opt ./data
          printf '%s' '${playerConfig}' > ./opt/server.properties.tmpl
          printf '%s' '${paperGlobalConfig}' > ./opt/paper-global.yml.tmpl
          printf '%s' '${whitelistJson}' > ./opt/whitelist.json
        '';
        config = {
          WorkingDir = "/data";
          Entrypoint = [ "/entrypoint.sh" ];
        };
      };

      proxyImage = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/guildedthorn/mc-velocity";
        tag = proxyTag;
        contents = [
          pkgs.coreutils
          pkgs.jdk25
          pkgs.gnused
          mcJars
          proxyEntrypoint
        ];
        extraCommands = ''
          mkdir -p ./opt ./data
          printf '%s' '${proxyConfig}' > ./opt/velocity.toml.tmpl
        '';
        config = {
          WorkingDir = "/data";
          Entrypoint = [ "/entrypoint.sh" ];
        };
      };

      autoscalerPy = pkgs.writeScript "mc-lobby-autoscaler.py" ''
        import argparse
        import json
        import re
        import socket
        import struct
        import subprocess
        import sys
        import time


        def rcon(host, port, password, cmd, timeout=3):
            def pack(rid, ptype, body):
                data = struct.pack("<iii", rid, ptype, len(body.encode()) + 1) + body.encode("utf-8") + b"\0\0"
                return struct.pack("<i", len(data)) + data

            def recv(sock):
                (n,) = struct.unpack("<i", sock.recv(4))
                data = b""
                while len(data) < n:
                    data += sock.recv(n - len(data))
                return data

            with socket.create_connection((host, port), timeout=timeout) as s:
                s.sendall(pack(1, 3, password))
                recv(s)
                s.sendall(pack(2, 2, cmd))
                body = recv(s)[12:].decode("utf-8", errors="replace").rstrip("\0")
                return body


        def kubectl(*args):
            return subprocess.run(
                ["kubectl"] + list(args), check=True, capture_output=True, text=True
            ).stdout


        def players_on(host, port, password):
            try:
                out = rcon(host, port, password, "list")
                m = re.search(r"There are (\d+) of a max of", out)
                return int(m.group(1)) if m else 0
            except Exception:
                return -1  # unreachable / not yet up


        def main():
            ap = argparse.ArgumentParser()
            ap.add_argument("--interval", type=int, default=30)
            ap.add_argument("--label", required=True)
            ap.add_argument("--deployment", required=True)
            ap.add_argument("--namespace", default="mc")
            ap.add_argument("--max-per-lobby", type=int, default=40)
            ap.add_argument("--max-lobbies", type=int, default=4)
            ap.add_argument("--rcon-port", type=int, default=25575)
            ap.add_argument("--rcon-password-file", required=True)
            args = ap.parse_args()

            with open(args.rcon_password_file) as fh:
                password = fh.read().strip()

            while True:
                try:
                    pods = json.loads(
                        kubectl(
                            "get", "pods", "-n", args.namespace, "-l", args.label, "-o", "json"
                        )
                    )
                    items = [
                        p
                        for p in pods["items"]
                        if not p["metadata"].get("deletionTimestamp")
                        and p["status"].get("phase") == "Running"
                    ]
                    ips = [p["status"].get("podIP") for p in items]
                    total = 0
                    live = 0
                    for ip in ips:
                        if not ip:
                            continue
                        count = players_on(ip, args.rcon_port, password)
                        if count >= 0:
                            live += 1
                            total += count
                    desired = max(1, min(args.max_lobbies, -(-total // args.max_per_lobby)))
                    if live and desired != len(ips):
                        print(f"scaling lobby pool: {len(ips)} -> {desired} ({total} players)")
                        kubectl(
                            "scale", "deployment/" + args.deployment,
                            "--replicas", str(desired),
                            "-n", args.namespace,
                        )
                except Exception as e:
                    print(f"autoscaler error: {e}", file=sys.stderr)
                time.sleep(args.interval)


        if __name__ == "__main__":
            main()
      '';

      mcNamespace = pkgs.writeText "mc-namespace.yaml" ''
        apiVersion: v1
        kind: Namespace
        metadata:
          name: ${cfg.namespace}
          labels:
            app: thornix-mc
      '';

      mcLobby = pkgs.writeText "mc-lobby.yaml" ''
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: ${cfg.identity}
          namespace: ${cfg.namespace}
          labels:
            app: ${cfg.identity}
        spec:
          replicas: 1
          selector:
            matchLabels:
              app: ${cfg.identity}
          strategy:
            type: RollingUpdate
            rollingUpdate:
              maxSurge: 1
              maxUnavailable: 0
          template:
            metadata:
              labels:
                app: ${cfg.identity}
            spec:
              containers:
                - name: lobby
                  image: localhost/guildedthorn/mc-lobby:${lobbyTag}
                  imagePullPolicy: IfNotPresent
                  envFrom:
                    - secretRef:
                        name: mc-secrets
                  ports:
                    - name: game
                      containerPort: ${toString cfg.lobbyPort}
                    - name: rcon
                      containerPort: ${toString cfg.rconPort}
                  readinessProbe:
                    tcpSocket:
                      port: ${toString cfg.lobbyPort}
                    initialDelaySeconds: 15
                    periodSeconds: 10
                  lifecycle:
                    preStop:
                      exec:
                        command: ["sh", "-c", "sleep 5"]
      '';

      mcLobbyService = pkgs.writeText "mc-lobby-service.yaml" ''
        apiVersion: v1
        kind: Service
        metadata:
          name: ${cfg.identity}
          namespace: ${cfg.namespace}
        spec:
          selector:
            app: ${cfg.identity}
          ports:
            - name: game
              port: ${toString cfg.lobbyPort}
              targetPort: ${toString cfg.lobbyPort}
            - name: rcon
              port: ${toString cfg.rconPort}
              targetPort: ${toString cfg.rconPort}
      '';

      mcVelocity = pkgs.writeText "mc-velocity.yaml" ''
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: mc-velocity
          namespace: ${cfg.namespace}
          labels:
            app: mc-velocity
        spec:
          replicas: 1
          selector:
            matchLabels:
              app: mc-velocity
          template:
            metadata:
              labels:
                app: mc-velocity
            spec:
              containers:
                - name: velocity
                  image: localhost/guildedthorn/mc-velocity:${proxyTag}
                  imagePullPolicy: IfNotPresent
                  envFrom:
                    - secretRef:
                        name: mc-secrets
                  ports:
                    - name: proxy
                      containerPort: ${toString cfg.lobbyPort}
                  readinessProbe:
                    tcpSocket:
                      port: ${toString cfg.lobbyPort}
                    initialDelaySeconds: 15
                    periodSeconds: 5
      '';

      mcVelocityService = pkgs.writeText "mc-velocity-service.yaml" ''
        apiVersion: v1
        kind: Service
        metadata:
          name: mc-velocity
          namespace: ${cfg.namespace}
        spec:
          type: LoadBalancer
          selector:
            app: mc-velocity
          ports:
            - name: proxy
              port: ${toString cfg.lobbyPort}
              targetPort: ${toString cfg.lobbyPort}
      '';
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

            k3s ctr -n k8s.io images import ${lobbyImage}
            k3s ctr -n k8s.io images import ${proxyImage}

            kubectl apply -f ${mcNamespace}
            kubectl create secret generic mc-secrets \
              -n ${cfg.namespace} \
              --from-file=FORWARDING_SECRET=${config.sops.secrets."minecraft/forwarding-secret".path} \
              --from-file=RCON_PASSWORD=${config.sops.secrets."minecraft/rcon-password".path} \
              --dry-run=client -o yaml | kubectl apply -f -
            kubectl apply -f ${mcLobby}
            kubectl apply -f ${mcLobbyService}
            kubectl apply -f ${mcVelocity}
            kubectl apply -f ${mcVelocityService}

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
                --rcon-password-file ${config.sops.secrets."minecraft/rcon-password".path}
            '';
            Restart = "always";
            RestartSec = "10s";
          };
        };
      };
    };
}
