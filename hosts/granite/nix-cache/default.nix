{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hostname = "cache.guildedthorn.arpa";

  # A separate Nix store on the platter keeps the served paths independent of
  # the host's normal nix-store --gc. Harmonia streams the NARs from here with
  # transparent zstd compression; clients still see /nix/store paths.
  storeRoot = "/platter/services/nix-cache";
  storeDir = "${storeRoot}/nix/store";
  dbDir = "${storeRoot}/nix/var/nix/db";
  dbPath = "${dbDir}/db.sqlite";
  rootDir = "${storeRoot}/nix/var/nix/gcroots/auto";

  nix = "${config.nix.package}/bin/nix";
  nixStore = "${config.nix.package}/bin/nix-store";
  cachix = "https://guildedthorn.cachix.org";

  # Granite's /etc/nixos is a deployment directory without flake.nix, so use
  # the exact flake source baked into this system closure instead.
  flakeSource = inputs.self.outPath;

  # Harmonia refuses to start until the SQLite database exists, but the first
  # populate may not happen until days after boot. Seed an empty database with
  # nix-store so the cache is immediately available.
  init = pkgs.writeShellScript "nix-cache-init" ''
    set -eu

    dbPath=${lib.escapeShellArg dbPath}
    if [ ! -f "$dbPath" ]; then
      ${lib.escapeShellArg nixStore} --store ${lib.escapeShellArg "local?root=${storeRoot}"} \
        --load-db </dev/null
    fi
  '';

  populate = pkgs.writeShellScript "nix-cache-populate" ''
    set -o pipefail

    flake=${lib.escapeShellArg flakeSource}
    storeRoot=${lib.escapeShellArg storeRoot}
    targetStore="local?root=$storeRoot"
    rootDir="$storeRoot/nix/var/nix/gcroots/auto"
    nix=${lib.escapeShellArg nix}
    nixStore=${lib.escapeShellArg nixStore}
    cachix=${lib.escapeShellArg cachix}

    mkdir -p "$rootDir"

    hosts=$($nix eval --raw --no-write-lock-file "$flake#nixosConfigurations" \
      --apply 'c: builtins.concatStringsSep " " (builtins.attrNames c)')

    copied=0
    cached=0
    failed=0

    for host in $hosts; do
      out=$($nix eval --raw --no-write-lock-file \
        "$flake#nixosConfigurations.$host.config.system.build.toplevel.outPath" 2>/dev/null) || {
        printf 'skip %-16s no eval\n' "$host"
        failed=$((failed + 1))
        continue
      }

      if [ -z "$out" ]; then
        printf 'skip %-16s no outPath\n' "$host"
        failed=$((failed + 1))
        continue
      fi

      if $nixStore --store "$targetStore" -qR "$out" >/dev/null 2>&1; then
        printf 'have %-16s %s\n' "$host" "$out"
        cached=$((cached + 1))
      elif $nixStore -qR "$out" >/dev/null 2>&1; then
        printf 'copy %-16s local store\n' "$host"
        # The target store has no reason to trust narinfo signatures from the
        # host store, so disable signature checks for this local-to-local copy.
        if $nix copy --no-check-sigs --to "$targetStore" "$out" >/dev/null; then
          copied=$((copied + 1))
        else
          failed=$((failed + 1))
          continue
        fi
      else
        printf 'pull %-16s cachix\n' "$host"
        if $nix copy --from "$cachix" --to "$targetStore" "$out" >/dev/null; then
          copied=$((copied + 1))
        else
          failed=$((failed + 1))
          continue
        fi
      fi

      if [ -d "$storeRoot$out" ]; then
        ln -sfn "$storeRoot$out" "$rootDir/$host"
      fi
    done

    printf 'nix-cache-populate: %s copied, %s already cached, %s failed\n' \
      "$copied" "$cached" "$failed"

    # Cap the dedicated store at roughly 180 GiB. The per-host symlinks above
    # are GC roots, so this drops only superseded generations.
    usage=$(du -sb "$storeRoot" | awk '{print $1}')
    if [ "$usage" -gt 193273528320 ]; then
      printf 'nix-cache-populate: store is %.1f GiB; collecting\n' \
        "$(awk -v b="$usage" 'BEGIN {print b / 1024 / 1024 / 1024}')"
      $nixStore --store "$targetStore" --gc --max-freed 21474836480
    fi
  '';
in
{
  assertions = [
    {
      assertion = config.networking.hostName == "granite";
      message = "the local Nix binary cache is intended for the granite host";
    }
  ];

  systemd.tmpfiles.rules = [
    "d ${storeRoot} 0755 root root -"
    "d ${storeDir} 0755 root root -"
    "d ${dbDir} 0755 root root -"
    "d ${rootDir} 0755 root root -"
  ];

  sops.secrets."nix-cache-signing-key" = {
    sopsFile = ./../nix-cache.secrets.yaml;
  };

  services.harmonia = {
    cache = {
      enable = true;
      signKeyPaths = [ config.sops.secrets."nix-cache-signing-key".path ];
      settings = {
        bind = "127.0.0.1:5000";
        workers = 8;
        # Prefer this cache over public Cachix when priorities are compared.
        priority = 10;
        enable_compression = true;
        virtual_nix_store = "/nix/store";
        real_nix_store = storeDir;
        nix_db_path = dbPath;
      };
    };
  };

  systemd.services."nix-cache-init" = {
    description = "Initialize the local Nix binary cache database";
    unitConfig.RequiresMountsFor = [ storeRoot ];
    path = [ config.nix.package ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = init;
      RemainAfterExit = true;
    };
  };

  # Harmonia is socket-activated. Pull in the initializer before its service
  # starts so a fresh boot does not answer requests with 502.
  systemd.services.harmonia = {
    requires = [ "nix-cache-init.service" ];
    after = [ "nix-cache-init.service" ];
  };

  systemd.services."nix-cache-populate" = {
    description = "Populate the local Nix binary cache from fleet closures";
    after = [
      "network-online.target"
      "zfs-mount.service"
    ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ storeRoot ];
    path = [
      config.nix.package
      pkgs.coreutils
      pkgs.gawk
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = populate;
      TimeoutStartSec = "1h";
    };
  };

  systemd.timers."nix-cache-populate" = {
    description = "Weekly refresh of the local Nix binary cache";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  # Forgejo owns granite's shared step-CA certificate. Add the cache name to
  # it just like the other LAN vhosts on this host.
  thorn.acme.extraDomainNames = [ hostname ];

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts.${hostname} = {
      serverName = hostname;
      forceSSL = true;
      useACMEHost = "forgejo.guildedthorn.arpa";
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "same-origin" always;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:5000";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_redirect http:// https://;
          proxy_http_version 1.1;
          proxy_buffering off;
          proxy_read_timeout 300s;
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
