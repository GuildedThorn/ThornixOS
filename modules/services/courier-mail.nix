{ inputs, ... }:
{
  nixos.modules.services-courier-mail =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "courier.guildedthorn.arpa";
      stateDirectory = "/var/lib/stalwart";
      configPath = "${stateDirectory}/config.json";
      bootstrapPasswordPath = "${stateDirectory}/bootstrap-admin-password";
      stalwartPackage = pkgs.stalwart_0_16;

      launcher = pkgs.writeShellScript "courier-stalwart-launch" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        # The recovery credential exists only while config.json is absent.
        # Completing Stalwart's bootstrap creates the real administrator and
        # atomically removes this backdoor from every subsequent process.
        if [[ ! -e ${lib.escapeShellArg configPath} ]]; then
          password_path=${lib.escapeShellArg bootstrapPasswordPath}
          if [[ ! -s "$password_path" ]]; then
            ${pkgs.openssl}/bin/openssl rand -base64 36 \
              | ${pkgs.coreutils}/bin/tr -d '\n' > "$password_path.new"
            printf '\n' >> "$password_path.new"
            chmod 0400 "$password_path.new"
            mv -T "$password_path.new" "$password_path"
          fi
          export STALWART_RECOVERY_ADMIN
          STALWART_RECOVERY_ADMIN="admin:$(${pkgs.coreutils}/bin/tr -d '\n' < "$password_path")"
        fi

        exec ${lib.getExe stalwartPackage} --config=${lib.escapeShellArg configPath}
      '';

      showBootstrapPassword = pkgs.writeShellApplication {
        name = "courier-bootstrap-password";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if [[ $EUID -ne 0 ]]; then
            echo "error: run courier-bootstrap-password as root" >&2
            exit 1
          fi
          if [[ -e ${lib.escapeShellArg configPath} ]]; then
            echo "Bootstrap is complete; the temporary recovery credential is no longer active."
            exit 1
          fi
          if [[ ! -s ${lib.escapeShellArg bootstrapPasswordPath} ]]; then
            echo "error: Courier has not generated its bootstrap credential yet" >&2
            exit 1
          fi
          printf 'username: admin\npassword: '
          tr -d '\n' < ${lib.escapeShellArg bootstrapPasswordPath}
          printf '\n'
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "courier";
          message = "services-courier-mail is a fixed service profile for the courier host";
        }
      ];

      # Stalwart 0.16 replaces its old TOML configuration with a tiny mutable
      # datastore pointer plus API-managed settings. The nixpkgs module still
      # targets 0.15, so Courier owns this narrowly scoped service definition
      # until upstream's module catches up. The flake-pinned binary, unit
      # hardening, firewall, machine identity, and bootstrap wrapper remain
      # fully declarative; mail domains/accounts are durable application data.
      users.groups.stalwart = { };
      users.users.stalwart = {
        isSystemUser = true;
        group = "stalwart";
        home = stateDirectory;
      };

      systemd.services.stalwart = {
        description = "Courier Stalwart mail and collaboration server";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [
          "local-fs.target"
          "network-online.target"
        ];
        serviceConfig = {
          Type = "simple";
          User = "stalwart";
          Group = "stalwart";
          WorkingDirectory = stateDirectory;
          StateDirectory = "stalwart";
          StateDirectoryMode = "0700";
          LogsDirectory = "stalwart";
          LogsDirectoryMode = "0750";
          UMask = "0077";
          ExecStart = launcher;
          Restart = "on-failure";
          RestartSec = 5;
          KillMode = "process";
          KillSignal = "SIGINT";
          LimitNOFILE = 65536;

          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
          DeviceAllow = [ "" ];
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          PrivateUsers = false;
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
          ];
        };
        environment = {
          STALWART_HOSTNAME = hostname;
          STALWART_PUBLIC_URL = "https://${hostname}";
          STALWART_RECOVERY_MODE_PORT = "8080";
          SSL_CERT_FILE = config.security.pki.caBundle;
        };
      };

      security.pki.certificates = [
        (builtins.readFile "${inputs.self}/certs/ThornCloud_CA.crt")
      ];

      environment.systemPackages = [
        stalwartPackage
        pkgs.stalwart-cli
        showBootstrapPassword
      ];
    };
}
