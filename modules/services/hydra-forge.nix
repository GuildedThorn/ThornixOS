{ inputs, ... }:
{
  nixos.modules.services-hydra-forge =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.forgePromotion;
      hostname = "forge.guildedthorn.arpa";
      stateDirectory = "/var/lib/thornix-promotion";
      # Pin GitHub's published Ed25519 host key rather than trusting DNS or
      # accepting a first-seen key on the machine that controls production.
      githubKnownHosts = pkgs.writeText "thornix-github-known-hosts" ''
        github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      '';
      promote = pkgs.writeShellApplication {
        name = "thornix-promote-production";
        runtimeInputs = with pkgs; [
          cachix
          findutils
          git
          nix
          openssh
        ];
        text = ''
          set -o errexit -o nounset -o pipefail

          repository=${lib.escapeShellArg "${stateDirectory}/repository"}
          remote=git@github.com:GuildedThorn/ThornixOS.git

          export HOME=${lib.escapeShellArg stateDirectory}
          export XDG_CACHE_HOME="$HOME/.cache"
          export GIT_TERMINAL_PROMPT=0
          export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -F /dev/null -i $CREDENTIALS_DIRECTORY/github-deploy-key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=${githubKnownHosts}"

          if [[ ! -d "$repository/.git" ]]; then
            git clone --filter=blob:none --no-checkout "$remote" "$repository"
          fi

          git -C "$repository" remote set-url origin "$remote"
          git -C "$repository" fetch --prune origin \
            '+refs/heads/main:refs/remotes/origin/main'

          if ! git -C "$repository" fetch origin \
            '+refs/heads/production:refs/remotes/origin/production'; then
            echo "production does not exist yet; leave GitHub bootstrap CI enabled" >&2
            exit 0
          fi

          main_commit=$(git -C "$repository" rev-parse refs/remotes/origin/main)
          production_commit=$(git -C "$repository" rev-parse refs/remotes/origin/production)
          if [[ "$main_commit" == "$production_commit" ]]; then
            exit 0
          fi
          if ! git -C "$repository" merge-base --is-ancestor \
            "$production_commit" "$main_commit"; then
            echo "refusing non-fast-forward production history" >&2
            exit 1
          fi

          # Hydra stamps each required aggregate with its exact source
          # revision. Prefer the newest completed main commit, but walk back
          # through recent revisions so frequent pushes cannot starve an
          # earlier known-good build. This store lookup is intentionally
          # evaluation-free: Hydra has already done the expensive fleet eval.
          candidate=
          required_path=
          while IFS= read -r revision; do
            aggregate_name="thornixos-production-required-$revision"
            evaluated=$(find /nix/store -mindepth 1 -maxdepth 1 -type d \
              -name "*-$aggregate_name" -print -quit)
            if [[ -n "$evaluated" ]] \
              && nix-store --check-validity "$evaluated" >/dev/null 2>&1; then
              candidate=$revision
              required_path=$evaluated
              break
            fi
          done < <(
            git -C "$repository" rev-list --first-parent --max-count=50 \
              refs/remotes/origin/main '^refs/remotes/origin/production'
          )

          if [[ -z "$candidate" ]]; then
            echo "Hydra has not completed a production aggregate newer than production"
            exit 0
          fi

          # Confirm the aggregate closure is present in Cachix before comin
          # can observe the branch update. The aggregate references every
          # constituent system, so this recursively covers the whole fleet.
          CACHIX_AUTH_TOKEN="$(<"$CREDENTIALS_DIRECTORY/cachix-token")"
          export CACHIX_AUTH_TOKEN
          cachix push guildedthorn "$required_path"

          git -C "$repository" push origin \
            "$candidate:refs/heads/production"
          printf 'Promoted ThornixOS production to %s\n' "$candidate"
        '';
      };
    in
    {
      options.thorn.forgePromotion = {
        enable = lib.mkEnableOption "Hydra-backed ThornixOS production promotion";
        githubDeployKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Repository-scoped GitHub SSH deploy key with write access to ThornixOS.";
        };
        cachixTokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Cachix auth token used to publish successful production closures.";
        };
      };

      config = lib.mkMerge [
        {
          services.hydra = {
            enable = true;
            hydraURL = "https://${hostname}";
            notificationSender = "hydra@guildedthorn.arpa";
            listenHost = "127.0.0.1";
            port = 3000;
            buildMachinesFiles = [ ];
            useSubstitutes = true;
            minimumDiskFree = 20;
            minimumDiskFreeEvaluator = 10;

            # Stylix resolves its pinned Base16 scheme through an IFD while
            # evaluating each host. Hydra defaults this off independently of
            # nix.conf, so opt in for this administrator-controlled jobset.
            # Builds remain sandboxed and flake inputs remain URI-allowlisted.
            extraConfig = ''
              allow_import_from_derivation = true
            '';
          };

          # Flake jobsets evaluate in restricted mode. Permit only the URI
          # families used by ThornixOS inputs; local paths remain forbidden.
          nix.settings = {
            allowed-uris = [
              "github:"
              "https://github.com/"
              "https://channels.nixos.org/"
              "git+https://github.com/"
              "git+https://codeberg.org/"
            ];
            # Forge starts with 8 vCPU and 16 GiB RAM. Two four-core builds
            # preserve throughput without six concurrent compilers fighting
            # for all eight cores and driving the VM into swap or OOM.
            max-jobs = 2;
            cores = 4;
          };

          # Hydra maintains GC roots for retained builds. Collect everything
          # else daily so transient source/build paths cannot strand the
          # queue runner at its free-space safety threshold.
          programs.nh.clean.dates = lib.mkForce "*-*-* 04:30:00";
          nix.optimise = {
            automatic = true;
            dates = "Sun *-*-* 05:30:00";
            randomizedDelaySec = "30min";
          };

          services.postgresqlBackup = {
            enable = true;
            databases = [ "hydra" ];
            startAt = "*-*-* 03:15:00";
            compression = "zstd";
          };

          thorn.acme = {
            enable = true;
            domain = hostname;
            group = config.services.nginx.group;
            reloadServices = [ "nginx.service" ];
          };

          services.nginx = {
            enable = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;
            recommendedGzipSettings = true;
            virtualHosts.${hostname} = {
              serverName = hostname;
              forceSSL = true;
              useACMEHost = hostname;
              extraConfig = ''
                add_header X-Content-Type-Options "nosniff" always;
                add_header Referrer-Policy "same-origin" always;
                add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
              '';
              locations."/" = {
                proxyPass = "http://127.0.0.1:3000";
                proxyWebsockets = true;
              };
            };
          };

          environment.systemPackages = [ promote ];
        }

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = cfg.githubDeployKeyFile != null;
              message = "thorn.forgePromotion.githubDeployKeyFile is required";
            }
            {
              assertion = cfg.cachixTokenFile != null;
              message = "thorn.forgePromotion.cachixTokenFile is required";
            }
          ];

          users.groups.thornix-promoter = { };
          users.users.thornix-promoter = {
            isSystemUser = true;
            group = "thornix-promoter";
            home = stateDirectory;
          };

          services.cachix-watch-store = {
            enable = true;
            cacheName = "guildedthorn";
            cachixTokenFile = cfg.cachixTokenFile;
            compressionLevel = 8;
            jobs = 2;
          };

          systemd.services.thornix-promote-production = {
            description = "Promote the newest Hydra-verified ThornixOS production revision";
            wants = [ "network-online.target" ];
            after = [
              "hydra-queue-runner.service"
              "network-online.target"
            ];
            serviceConfig = {
              Type = "oneshot";
              User = "thornix-promoter";
              Group = "thornix-promoter";
              StateDirectory = "thornix-promotion";
              StateDirectoryMode = "0700";
              LoadCredential = [
                "github-deploy-key:${toString cfg.githubDeployKeyFile}"
                "cachix-token:${toString cfg.cachixTokenFile}"
              ];
              CapabilityBoundingSet = "";
              LockPersonality = true;
              NoNewPrivileges = true;
              PrivateDevices = true;
              PrivateTmp = true;
              ProtectClock = true;
              ProtectControlGroups = true;
              ProtectHome = true;
              ProtectHostname = true;
              ProtectKernelLogs = true;
              ProtectKernelModules = true;
              ProtectKernelTunables = true;
              ProtectSystem = "strict";
              ReadWritePaths = [ stateDirectory ];
              RestrictAddressFamilies = [
                "AF_INET"
                "AF_INET6"
                "AF_UNIX"
              ];
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              SystemCallArchitectures = "native";
              UMask = "0077";
            };
            script = lib.getExe promote;
          };

          systemd.timers.thornix-promote-production = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "10m";
              OnUnitInactiveSec = "10m";
              RandomizedDelaySec = "20s";
              Persistent = true;
              Unit = "thornix-promote-production.service";
            };
          };
        })
      ];
    };
}
