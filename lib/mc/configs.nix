# Pure config renderers for the Minecraft lobby pool. Each binding returns the
# text of a file the container entrypoints materialise at start (the *.tmpl
# templates) or a generated JSON document (whitelist/ops). Keeping these apart
# from the image builder lets the content-addressed tag hash cover exactly the
# rendered bytes.
{ lib, cfg }:
{
  # server.properties template. Secrets are left as placeholders and filled in
  # by the entrypoint so they never enter the store or the image.
  playerProperties = ''
    eula=true
    level-type=flat
    motd=${cfg.networkName}
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

  # Modern Paper (1.19+) reads Velocity forwarding from paper-global.yml, not
  # server.properties. `_version` must accompany a partial override.
  paperGlobal = ''
    _version: 31
    proxies:
      velocity:
        enabled: true
        online-mode: true
        secret: __FORWARDING_SECRET__
  '';

  # Velocity 4.x config-version 2.9: player forwarding is a top-level mode plus
  # a separate forwarding.secret file (no [forwarding] section).
  velocity = ''
    config-version = "2.9"
    bind = "0.0.0.0:${toString cfg.lobbyPort}"
    motd = "<#09add3>${cfg.networkName}"
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

  # Whitelist / ops are keyed by Mojang UUID: the Velocity proxy authenticates
  # players online, so the backend sees each player's real account UUID rather
  # than an offline-mode name derivation.
  whitelistJson = builtins.toJSON (map (p: { inherit (p) name uuid; }) cfg.whitelist);

  opsJson = builtins.toJSON (
    map (p: {
      inherit (p) name uuid;
      level = 4;
      bypassesPlayerLimit = false;
    }) cfg.ops
  );
}
