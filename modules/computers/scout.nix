{ config, inputs, ... }:
{
  flake.nixosConfigurations.scout = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-intel
      config.nixos.modules.desktop-hyprland

      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-clamav
      config.nixos.modules.services-fingerprint
      config.nixos.modules.services-keybase
      config.nixos.modules.services-obs
      config.nixos.modules.services-spicetify
      config.nixos.modules.services-sdr
      config.nixos.modules.services-ssh

      config.nixos.modules.thorn-glance

      "${inputs.self}/hosts/scout/hardware-configuration.nix"
      "${inputs.self}/hosts/scout/networking.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/scout/home.nix"; }

      (
        {
          pkgs,
          lib,
          ...
        }:
        {
          environment.systemPackages = with pkgs; [
            networkmanager

            corectrl

            openrgb

            nwg-displays
            nwg-look

            glance

            brightnessctl

            komikku
            jellyfin-desktop

            teamspeak6-client
            element-desktop
            telegram-desktop

            blender

            krita

            kdePackages.kdenlive

            orca-slicer

            fritzing

            plasticity

            ethtool
            piper

            rofi-obsidian

            chirp

            codex
            claude-code

            postman

            keepassxc

            system-config-printer

            android-studio
            android-tools

            mixxx
            hydrogen

            gphoto2
          ];

          # -------------------------
          # Bootloader (UEFI systems)
          # -------------------------
          boot.loader.systemd-boot.enable = false;
          boot.loader.efi.canTouchEfiVariables = true;
          boot.initrd.systemd.enable = true;

          boot.lanzaboote = {
            enable = true;
            pkiBundle = "/var/lib/sbctl";
          };

          networking.networkmanager.enable = true;

          services.printing = {
            enable = true;
            drivers = with pkgs; [
              cups-filters
              cups-browsed
              gutenprint
              canon-cups-ufr2
            ];
          };

          boot.kernelParams = [
            "acpi_backlight=native"
            #"snd_intel_dspcfg.dsp_driver=3"
            #"snd_intel_dspcfg.dsp_driver=1"
            #"snd_hda_intel.dmic_detect=0"
          ];

          services.hardware.openrgb = {
            enable = true;
            package = pkgs.openrgb-with-all-plugins;
          };

          programs.gphoto2.enable = true;

          programs.npm.enable = true;

          programs.corectrl = {
            enable = true;
          };

          programs.thunar.enable = true;
          programs.thunar.plugins = with pkgs; [
            thunar-archive-plugin
            thunar-volman
          ];

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

          hardware.gpgSmartcards.enable = true;
          hardware.firmware = [ pkgs.sof-firmware ];

          services.ananicy.enable = true;

          services.earlyoom.enable = true;

          services.fwupd.enable = true;

          services.ratbagd.enable = true;

          services.pcscd.enable = true;
          services.pcscd.plugins = [ pkgs.ccid ];

          services.flatpak.enable = true;
          services.flatpak.packages = [
            {
              appId = "com.mongodb.Compass";
              origin = "flathub";
            }
          ];

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

          services.upower.enable = true;

          services.tlp = {
            enable = true;
            settings = {
              CPU_SCALING_GOVERNOR_ON_AC = "performance";
              CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

              CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
              CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

              CPU_MIN_PERF_ON_AC = 0;
              CPU_MAX_PERF_ON_AC = 100;
              CPU_MIN_PERF_ON_BAT = 0;
              CPU_MAX_PERF_ON_BAT = 20;

              # Optional helps save long term battery health
              START_CHARGE_THRESH_BAT0 = 75; # 40 and below it starts to charge
              STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
            };
          };

          services.thinkfan = {
            enable = true;

            sensors = [
              {
                query = "/proc/acpi/ibm/thermal";
                type = "tpacpi";
              }
            ];

            fans = [
              {
                query = "/proc/acpi/ibm/fan";
                type = "tpacpi";
              }
            ];

            # Aggressive fan curve
            levels = [
              [
                0
                0
                35
              ]
              [
                1
                33
                40
              ]
              [
                2
                38
                45
              ]
              [
                3
                43
                50
              ]
              [
                4
                48
                55
              ]
              [
                5
                53
                60
              ]
              [
                6
                58
                65
              ]
              [
                7
                63
                70
              ]
              [
                7
                68
                32767
              ] # full blast above ~68°C
            ];
          };

          services.thermald.enable = true;

          zramSwap = {
            enable = true;
            memoryPercent = 25;
          };

          system.autoUpgrade = {
            enable = true;
            allowReboot = false;
          };

          security.polkit.enable = true;

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

          security.pam.services.sddm.u2fAuth = true;
          security.pam.services.sudo.u2fAuth = true;
        }
      )
    ];
  };
}
