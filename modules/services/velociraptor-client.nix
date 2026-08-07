{ ... }:
{
  nixos.modules.services-velociraptor-client =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.velociraptorClient;
      secretName = "velociraptor_client_config";
      secretPath = config.sops.secrets.${secretName}.path;
      velociraptor = pkgs.callPackage ../../packages/velociraptor.nix { };
      credentialPath = "%d/client.config.yaml";

      validateConfig = pkgs.writeShellScript "velociraptor-client-config-check" ''
        set -o errexit -o nounset -o pipefail

        config_file="$1"
        test -s "$config_file"

        # Parse the complete generated configuration without printing it. The
        # URL and nonce checks reject an empty, server-side, or wrong-deployment
        # secret before a privileged endpoint process starts.
        ${lib.getExe velociraptor} \
          --config "$config_file" config show >/dev/null
        ${pkgs.gnugrep}/bin/grep -Fq \
          'https://hound.guildedthorn.arpa:8000/' "$config_file"
        ${pkgs.gnugrep}/bin/grep -Eq \
          '^[[:space:]]*nonce:[[:space:]]*[^[:space:]]+' "$config_file"
      '';
    in
    {
      options.thorn.velociraptorClient = {
        enable = lib.mkEnableOption "Hound Velociraptor endpoint client";

        sopsFile = lib.mkOption {
          type = lib.types.path;
          description = ''
            Binary-format SOPS file containing Hound's generated client YAML.
            It must be encrypted to the endpoint's installed SSH-derived age
            recipient and must never be placed in the Nix store as plaintext.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
            message = "The pinned Velociraptor endpoint binary is for x86_64-linux";
          }
          {
            assertion = builtins.pathExists cfg.sopsFile;
            message = "The Velociraptor client SOPS file does not exist";
          }
        ];

        environment.systemPackages = [ velociraptor ];

        sops.secrets.${secretName} = {
          sopsFile = cfg.sopsFile;
          format = "binary";
          mode = "0400";
          restartUnits = [ "velociraptor-client.service" ];
        };

        systemd.services.velociraptor-client = {
          description = "Hound Velociraptor endpoint client";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "sops-nix.service"
          ];

          serviceConfig = {
            Type = "simple";
            User = "root";
            Group = "root";
            LoadCredential = [
              "client.config.yaml:${secretPath}"
            ];
            ExecStartPre = "${validateConfig} ${credentialPath}";
            ExecStart = "${lib.getExe velociraptor} --config ${credentialPath} client";
            Restart = "always";
            RestartSec = "15s";
            TimeoutStopSec = "45s";
            UMask = "0077";

            # A DFIR agent intentionally needs complete host visibility and
            # response access, so filesystem/device/network namespaces would
            # make it ineffective. These controls still prevent privilege
            # expansion and several classes of process-level abuse without
            # hiding evidence from collections.
            LockPersonality = true;
            NoNewPrivileges = true;
            RestrictRealtime = true;
            SystemCallArchitectures = "native";
          };
        };
      };
    };
}
