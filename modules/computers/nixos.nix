{ config, inputs, ... }:
{
  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core
      inputs.hjem.nixosModules.default

      config.nixos.modules.desktop-hyprland
      config.nixos.modules.processor-amd
      config.nixos.modules.graphics-amd

      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-clamav
      config.nixos.modules.services-crowdsec
      config.nixos.modules.services-displaylink
      config.nixos.modules.services-fingerprint
      config.nixos.modules.services-keybase
      config.nixos.modules.services-obs
      config.nixos.modules.services-ollama
      config.nixos.modules.services-retroarch
      config.nixos.modules.services-spicetify
      config.nixos.modules.services-sdr
      config.nixos.modules.services-ssh
      config.nixos.modules.services-steam
      config.nixos.modules.services-tablets
      config.nixos.modules.services-velociraptor-client
      config.nixos.modules.services-vr

      config.nixos.modules.thorn-glance

      config.nixos.modules.hardware-nixos
      "${inputs.self}/hosts/nixos/disko.nix"
      "${inputs.self}/hosts/nixos/networking.nix"
      "${inputs.self}/hosts/nixos/secrets.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/nixos/home.nix"; }

      (
        { pkgs, ... }:
        {
          # Backport nixpkgs #548045; Coin3D's vendored Expat crashes FreeCAD
          # when Python 3.14 parses XML.
          nixpkgs.overlays = [
            (final: prev: {
              coin3d = prev.coin3d.overrideAttrs (oldAttrs: {
                buildInputs = (oldAttrs.buildInputs or [ ]) ++ [ final.expat ];
                cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [
                  (final.lib.cmakeBool "USE_EXTERNAL_EXPAT" true)
                ];
              });
            })
          ];

          hjem.users.thorn.packages = [ pkgs.freecad ];
          hjem.users.thorn.files = {
            ".local/share/FreeCAD/v1-1/Mod/FreeCADMCP".source =
              inputs."opencode-freecad-mcp-src" + "/addon/FreeCADMCP";

            ".local/share/FreeCAD/v1-1/freecad_mcp_settings.json" = {
              type = "copy";
              clobber = true;
              permissions = "0600";
              text = builtins.toJSON {
                # RPC exposes arbitrary Python execution, so start it only
                # for sessions where OpenCode needs FreeCAD control.
                remote_enabled = false;
                allowed_ips = "127.0.0.1";
                auto_start_rpc = false;
              };
            };
          };

          environment.systemPackages = with pkgs; [
            corectrl
            openrgb

            displaylink

            nwg-displays
            nwg-look

            jellyfin-desktop

            teamspeak6-client
            element-desktop
            telegram-desktop
            slack

            blender

            krita

            kdePackages.kdenlive

            orca-slicer

            fritzing

            steam
            steam-run
            steamcmd

            oversteer
            piper

            heroic
            osu-lazer-bin
            clonehero

            openvpn

            retroarch
            libretro.pcsx-rearmed
            libretro.pcsx2

            chirp

            arduino
            arduino-ide

            codex
            claude-code

            virt-viewer

            keepassxc

            system-config-printer

            android-studio
            android-tools

            mixxx
            hydrogen

            openxr-loader
            xrizer
            wayvr

            wakatime-cli

            swaybg
            mpvpaper
            cage
            grim
            ffmpeg
            steamcmd
          ];

          # -------------------------
          # Bootloader (UEFI systems)
          # -------------------------
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
          boot.initrd.systemd.enable = true;

          virtualisation.docker.enable = true;

          services.printing = {
            enable = true;
            drivers = with pkgs; [
              cups-filters
              cups-browsed
              gutenprint
              canon-cups-ufr2
            ];
          };

          services.hardware.openrgb = {
            enable = true;
            package = pkgs.openrgb-with-all-plugins;
          };

          services.flatpak.packages = [
            {
              appId = "org.vinegarhq.Sober";
              origin = "flathub";
            }
            {
              appId = "org.vinegarhq.Vinegar";
              origin = "flathub";
            }
            {
              appId = "io.github.glaumar.QRookie";
              origin = "flathub";
            }
            {
              appId = "org.gnome.gitlab.cheywood.Pulp";
              origin = "flathub";
            }
            {
              appId = "com.mongodb.Compass";
              origin = "flathub";
            }
          ];

          programs.npm.enable = true;

          programs.corectrl = {
            enable = true;
          };

          programs.gnupg.agent = {
            enable = true;
            enableSSHSupport = false;
          };

          programs.direnv = {
            enable = true;
            nix-direnv.enable = true;
          };

          programs.starship = {
            enable = true;
          };

          programs.appimage.enable = true;
          programs.appimage.binfmt = true;

          programs.seahorse.enable = true;
          programs.dconf.enable = true;

          programs.steam.remotePlay.openFirewall = true;
          programs.nix-ld.enable = true;

          hardware.gpgSmartcards.enable = true;

          services.ananicy.enable = true;

          services.earlyoom.enable = true;

          services.fwupd.enable = true;

          services.ratbagd.enable = true;

          services.pcscd.enable = true;
          services.pcscd.plugins = [ pkgs.ccid ];

          services.flatpak.enable = true;

          systemd.oomd.enable = true;

          services.dbus.enable = true;

          services.udev.packages = with pkgs; [
            yubikey-personalization
          ];

          services.avahi = {
            enable = true;
            nssmdns4 = true;
            openFirewall = true;
          };

          services.gvfs.enable = true;
          services.udisks2.enable = true;

          zramSwap = {
            enable = true;
            memoryPercent = 25;
          };

          security.polkit.enable = true;
          security.rtkit.enable = true;

          services.ollama.package = pkgs.ollama-vulkan;

          security.pam.u2f = {
            enable = true;
            control = "sufficient";

            settings = {
              cue = true;
              interactive = true;
            };
          };

          boot.tmp.useTmpfs = true;
          boot.tmp.tmpfsSize = "8G";

          # The workstation produces large development and gaming logs. Keep
          # the local incident window bounded; fleet telemetry remains on the
          # SOC and old Nix generations are still retained by nh's keep rules.
          programs.nh.clean.dates = "daily";
          security.auditd.settings = {
            max_log_file = 100;
            num_logs = 10;
          };
          services.journald.extraConfig = ''
            SystemMaxUse=2G
            RuntimeMaxUse=256M
            MaxRetentionSec=14day
          '';

          security.pam.services.sddm.u2fAuth = true;
          security.pam.services.sudo.u2fAuth = true;
        }
      )
    ];
  };
}
