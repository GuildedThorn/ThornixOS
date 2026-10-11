# Container entrypoints. They render the baked templates against the secrets
# injected by envFrom, then exec the JVM, so no secret is ever written into the
# store or image. Each script is wrapped in a directory because
# buildLayeredImage `contents` entries must be directory trees.
{ pkgs, cfg }:
{
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
      cp /opt/ops.json /data/ops.json
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
}
