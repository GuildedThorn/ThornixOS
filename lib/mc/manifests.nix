# Kubernetes manifests for the lobby pool and the Velocity proxy. Rendered from
# the option values plus the content-addressed image tags produced by
# lib/mc/images.nix.
{
  pkgs,
  cfg,
  lobbyTag,
  proxyTag,
}:
{
  namespace = pkgs.writeText "mc-namespace.yaml" ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${cfg.namespace}
      labels:
        app: thornix-mc
  '';

  lobby = pkgs.writeText "mc-lobby.yaml" ''
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

  lobbyService = pkgs.writeText "mc-lobby-service.yaml" ''
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

  velocity = pkgs.writeText "mc-velocity.yaml" ''
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

  velocityService = pkgs.writeText "mc-velocity-service.yaml" ''
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
}
