{ inputs, ... }:
{
  homeManager.modules.thorn =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      runtime = import ../../lib/crt-runtime.nix {
        inherit
          config
          inputs
          lib
          osConfig
          pkgs
          ;
      };
      inherit (runtime)
        cfg
        desktopState
        ewwScss
        ewwYuck
        siemReview
        socFeed
        socStats
        telemetryReaderCertificate
        ;
    in
    {
      options.thorn.desktop.crt = {
        enable = lib.mkEnableOption "eww SOC widget display for the CRT monitor";

        monitor = lib.mkOption {
          type = lib.types.str;
          default = "DP-1";
          description = "Output name the SOC display window opens on.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = builtins.pathExists telemetryReaderCertificate;
            message = ''
              certs/telemetry-reader.crt is missing. Sign the workstation
              reader CSR with ThornCloud_CA before enabling the CRT client.
            '';
          }
        ];

        programs.eww = {
          enable = true;
          yuckConfig = ewwYuck;
          scssConfig = ewwScss;
          # Daemon as a user service. Deliberately NOT hyprland exec-once:
          # with configType = "lua" a dash-keyed settings entry ("exec-once")
          # generates invalid Lua and poisons the whole hyprland config.
          systemd.enable = true;
        };

        systemd.user.services.eww-soc-crt = {
          Unit = {
            Description = "Open the SOC display on the CRT";
            After = [ "eww.service" ];
            BindsTo = [ "eww.service" ];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Retry loop: After= only orders against daemon start, not against
            # its IPC socket being ready.
            ExecStart = "${pkgs.writeShellScript "eww-open-soc-crt" ''
              for _ in $(seq 15); do
                ${config.programs.eww.package}/bin/eww open soc-crt && exit 0
                sleep 1
              done
              exit 1
            ''}";
            ExecStop = "${config.programs.eww.package}/bin/eww close soc-crt";
          };
          Install.WantedBy = [ "eww.service" ];
        };

        systemd.user.services.siem-review = {
          Unit = {
            Description = "Scheduled SIEM log review (Claude analyst pass)";
            After = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${siemReview}/bin/siem-review";
          };
        };

        systemd.user.timers.siem-review = {
          Unit.Description = "SIEM review three times daily";
          Timer = {
            OnCalendar = [
              "06:52"
              "14:52"
              "22:52"
            ];
            Persistent = true;
            RandomizedDelaySec = "5m";
          };
          Install.WantedBy = [ "timers.target" ];
        };

        home.packages = [
          desktopState
          socStats
          socFeed
          siemReview
        ];
      };
    };
}
