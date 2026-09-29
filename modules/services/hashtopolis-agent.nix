{
  nixos.modules.services-hashtopolis-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.hashtopolisAgent;

      stateDirectory = "/var/lib/hashtopolis-agent";
      secretName = "hashtopolis_agent_voucher";

      # Upstream ships a zip of __main__.py plus the htpclient package and has
      # no build metadata, so declare the package here and run the entrypoint
      # from a stable copy in $out. Updating the agent is a flake input bump,
      # not something the running agent should do to its own store path.
      agent = pkgs.python3.pkgs.buildPythonApplication {
        pname = "hashtopolis-agent";
        version = "0.7.6";

        src = pkgs.fetchFromGitHub {
          owner = "hashtopolis";
          repo = "agent-python";
          rev = "v0.7.6";
          hash = "sha256-wHeJLYFt8eiguj64T/8iiH6Z0zrb3o3lsDinw1cb2fs=";
        };

        format = "pyproject";

        nativeBuildInputs = [ pkgs.python3.pkgs.setuptools ];

        propagatedBuildInputs = with pkgs.python3.pkgs; [
          requests
          psutil
        ];

        postPatch = ''
          cat > pyproject.toml <<'EOF'
          [build-system]
          requires = ["setuptools"]
          build-backend = "setuptools.build_meta"

          [project]
          name = "hashtopolis-agent"
          version = "0.7.6"

          [tool.setuptools]
          packages = ["htpclient"]
          EOF

          # Fix bug: agent uses cert (client cert) instead of verify (CA bundle)
          sed -i 's/Session().s.cert = cert/Session().s.verify = cert/' htpclient/initialize.py
        '';

        # __main__.py is the zip entrypoint rather than an importable module,
        # so it is copied to a stable path and driven through runpy. Writing a
        # plain script into $out/bin rather than hand-rolling a wrapper around
        # the bare interpreter is deliberate: wrapPythonPrograms then injects
        # the PYTHONPATH that propagatedBuildInputs need at run time.
        postInstall = ''
          install -Dm644 __main__.py $out/share/hashtopolis-agent/__main__.py
          mkdir -p $out/bin
          cat > $out/bin/hashtopolis-agent <<EOF
          #!${pkgs.python3.interpreter}
          import runpy
          runpy.run_path("$out/share/hashtopolis-agent/__main__.py", run_name="__main__")
          EOF
          chmod +x $out/bin/hashtopolis-agent
        '';

        # The agent phones home to fetch its own updates; against a read-only
        # store path that either fails noisily or clobbers a shared path.
        doCheck = false;
        meta.mainProgram = "hashtopolis-agent";
      };

      # The voucher is a single-use registration credential, so it is read
      # from the sops-decrypted file at seed time rather than substituted
      # into this script. Substituting it would place the plaintext voucher
      # in the nix store, readable by every local user.
      seedConfig = pkgs.writeShellScript "hashtopolis-agent-seed-config" ''
        set -euo pipefail

        config=${lib.escapeShellArg "${stateDirectory}/config.json"}
        voucher_file=/run/secrets/${secretName}

        if [[ ! -e "$config" ]]; then
          umask 0077
          # A newline-terminated read so the value is valid JSON even if the
          # decrypted file lacks a trailing newline.
          voucher=$(cat "$voucher_file")
          cat > "$config" <<EOF
        {
          "url": ${lib.toJSON cfg.url},
          "voucher": ${lib.toJSON "$voucher"},
          "cert": ${lib.toJSON cfg.cert}
        }
        EOF
          chmod 0600 "$config"
        fi
      '';
    in
    {
      options.thorn.hashtopolisAgent = {
        enable = lib.mkEnableOption "the Hashtopolis cracking agent";

        url = lib.mkOption {
          type = lib.types.str;
          example = "http://nixos.guildedthorn.arpa:8080/api/server.php";
          description = ''
            Client API endpoint of the Hashtopolis server this agent registers
            with. Must address the backend container's `api/server.php`; the
            Angular frontend does not serve the agent API.
          '';
        };

        sopsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "./hosts/nixos/hashtopolis-agent.sops";
          description = ''
            SOPS file holding this host's single-use registration voucher under
            the `hashtopolis_agent_voucher` key. It must be encrypted to the
            recipient derived from this host's SSH host key.

            Prefer this over a plaintext `voucher` string: the seed script runs
            as the agent account and would otherwise bake the voucher into the
            nix store, where every local user can read it.
          '';
        };

        voucher = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Registration voucher issued by the server, consumed once during
            agent registration. Only used when `sopsFile` is null; leave empty
            otherwise. Enabling the agent without either would leave the unit
            blocked on an interactive prompt that no tty can ever answer.
          '';
        };

        cpuOnly = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Register as a CPU-only agent. Leave this off for the GPU hosts, or
            Hashtopolis will route their tasks to agents that cannot use them.
          '';
        };

        debug = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Run the agent with debug logging.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional arguments appended to the agent invocation. Useful for
            `--files-path` style overrides when the defaults under
            /var/lib/hashtopolis-agent are not wanted.
          '';
        };

        cert = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = "/run/hashtopolis-agent-ca/hashtopolis-ca-bundle.crt";
          description = ''
            Path to CA certificate bundle for TLS verification. The agent's
            bundled certifi may not include Let's Encrypt or other CAs used by
            the Hashtopolis server. Defaults to combined bundle with ThornCloud CA.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        users.groups.hashtopolis-agent = { };
        users.users.hashtopolis-agent = {
          isSystemUser = true;
          group = "hashtopolis-agent";
          home = stateDirectory;
          description = "Hashtopolis cracking agent";
        };

        environment.systemPackages = [ agent ];

        # The seed unit runs as the agent account, so the decrypted voucher has
        # to be readable by it. sops-nix defaults to root:root 0400, which
        # would make the seed step fail on a permission error instead of a
        # missing voucher.
        sops.secrets.${secretName} = lib.mkIf (cfg.sopsFile != null) {
          sopsFile = cfg.sopsFile;
          owner = "hashtopolis-agent";
          mode = "0400";
          restartUnits = [ "hashtopolis-agent-config.service" ];
        };

        systemd.tmpfiles.rules = [
          "d ${stateDirectory} 0750 hashtopolis-agent hashtopolis-agent -"
          "d ${stateDirectory}/files 0750 hashtopolis-agent hashtopolis-agent -"
          "d ${stateDirectory}/crackers 0750 hashtopolis-agent hashtopolis-agent -"
          "d ${stateDirectory}/hashlists 0750 hashtopolis-agent hashtopolis-agent -"
          "d ${stateDirectory}/zaps 0750 hashtopolis-agent hashtopolis-agent -"
          # Create combined CA bundle with system certs + ThornCloud chain
          "d /run/hashtopolis-agent-ca 0755 root root -"
        ];

        systemd.services.hashtopolis-agent-ca = {
          description = "Create combined CA bundle for Hashtopolis agent";
          before = [ "hashtopolis-agent-config.service" ];
          wantedBy = [ "hashtopolis-agent-config.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.bash}/bin/bash -c 'cat /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/thorncloud-ca-chain.crt > /run/hashtopolis-agent-ca/hashtopolis-ca-bundle.crt'";
          };
        };

        systemd.services.hashtopolis-agent-config = {
          description = "Seed the Hashtopolis agent config";
          before = [ "hashtopolis-agent.service" ];
          wantedBy = [ "hashtopolis-agent.service" ];
          # sops-nix must have written /run/secrets before the seed unit reads
          # the voucher out of it.
          after = [ "sops-nix.service" ];
          wants = [ "sops-nix.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "hashtopolis-agent";
            Group = "hashtopolis-agent";
            StateDirectory = "hashtopolis-agent";
            StateDirectoryMode = "0750";
            UMask = "0077";
            ExecStart = seedConfig;
            RemainAfterExit = true;
          };
        };

        systemd.services.hashtopolis-agent = {
          description = "Hashtopolis cracking agent";
          wantedBy = [ "multi-user.target" ];
          requires = [ "hashtopolis-agent-config.service" ];
          after = [
            "hashtopolis-agent-config.service"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          restartTriggers = [
            seedConfig
            agent
          ];

          serviceConfig = {
            Type = "simple";
            User = "hashtopolis-agent";
            Group = "hashtopolis-agent";
            # The agent resolves config.json relative to the working directory
            # and rewrites it in place to persist the issued API token.
            # Agent bug: uses cert param (client cert) instead of verify (CA bundle).
            # Workaround: REQUESTS_CA_BUNDLE env var which requests respects.
            Environment = "REQUESTS_CA_BUNDLE=${cfg.cert}";
            WorkingDirectory = stateDirectory;
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe agent)
                "--disable-update"
              ]
              ++ cfg.extraArgs
              ++ lib.optionals cfg.debug [ "--debug" ]
              ++ lib.optionals cfg.cpuOnly [ "--cpu-only" ]
            );
            Restart = "on-failure";
            RestartSec = "15s";
            TimeoutStopSec = "5min";
            UMask = "0077";

            # hashcat needs the OpenCL runtime, so /dev/dri and the render
            # group stay available; nothing else on the host is exposed.
            SupplementaryGroups = [
              "render"
              "video"
            ];
            DeviceAllow = [ "/dev/dri/renderD* rw" ];
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            ReadWritePaths = [ stateDirectory ];
          };
        };
      };
    };
}
