# Lobby (Paper backend) and Velocity proxy container images. Tags are
# content-addressed: any change to baked config, entrypoints, JVM, or server
# jars yields a new tag, so `kubectl apply` rolls pods even under
# imagePullPolicy: IfNotPresent.
{
  pkgs,
  cfg,
  configs,
  entrypoints,
}:
let
  inherit (entrypoints) lobbyEntrypoint proxyEntrypoint;

  shortHash = s: builtins.substring 0 12 (builtins.hashString "sha256" s);

  lobbyTag = "${cfg.environment}-${
    shortHash (
      configs.playerProperties
      + configs.paperGlobal
      + configs.whitelistJson
      + configs.opsJson
      + toString lobbyEntrypoint
      + toString pkgs.coreutils
      + pkgs.jdk25.version
      + pkgs.papermc.version
    )
  }";

  proxyTag = "${cfg.environment}-${
    shortHash (
      configs.velocity
      + toString proxyEntrypoint
      + toString pkgs.coreutils
      + pkgs.jdk25.version
      + pkgs.velocity.version
    )
  }";

  # Jars are unpacked to a stable layout so the image never depends on upstream
  # output names. Swapping the backend server jar (e.g. to a Leaf build) is a
  # one-line change here.
  mcJars = pkgs.runCommand "mc-server-jars" { } ''
    mkdir -p $out
    cp ${pkgs.papermc}/share/papermc/papermc.jar $out/lobby.jar
    cp ${pkgs.velocity}/share/velocity/velocity.jar $out/velocity.jar
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
      printf '%s' '${configs.playerProperties}' > ./opt/server.properties.tmpl
      printf '%s' '${configs.paperGlobal}' > ./opt/paper-global.yml.tmpl
      printf '%s' '${configs.whitelistJson}' > ./opt/whitelist.json
      printf '%s' '${configs.opsJson}' > ./opt/ops.json
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
      printf '%s' '${configs.velocity}' > ./opt/velocity.toml.tmpl
    '';
    config = {
      WorkingDir = "/data";
      Entrypoint = [ "/entrypoint.sh" ];
    };
  };
in
{
  inherit
    lobbyTag
    proxyTag
    lobbyImage
    proxyImage
    ;
}
