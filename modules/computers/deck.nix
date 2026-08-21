{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/deck/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.deck = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core
      inputs.jovian-nixos.nixosModules.jovian

      config.nixos.modules.desktop-kde-wle
      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-ssh

      "${inputs.self}/hosts/deck/disko.nix"
      "${inputs.self}/hosts/deck/networking.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/deck/home.nix"; }

      (
        {
          lib,
          pkgs,
          ...
        }:
        {
          nixpkgs.overlays = [
            inputs.jovian-nixos.overlays.jovian
            (_final: prev: {
              # Current nixpkgs already carries Jovian's MangoHud backports.
              mangohud = prev.mangohud.overrideAttrs (old: {
                patches = lib.unique (old.patches or [ ]);
              });
            })
          ];

          jovian = {
            devices.steamdeck.enable = true;
            steam = {
              enable = true;
              autoStart = true;
              user = "thorn";
              desktopSession = "plasma";
            };
          };

          boot = {
            kernelPackages = lib.mkForce pkgs.linuxPackages_jovian;
            loader = {
              systemd-boot.enable = true;
              efi.canTouchEfiVariables = true;
            };
            initrd.systemd.enable = true;
          };

          services = {
            fwupd.enable = true;
            upower.enable = true;

            pipewire.systemWide = true;

            openssh.settings = {
              KbdInteractiveAuthentication = false;
              PasswordAuthentication = false;
              PermitRootLogin = "prohibit-password";
            };

            wyoming.satellite = {
              enable = true;
              user = "voice";
              group = "voice";
              name = "Deck Voice";
              area = "Portable";
              uri = "tcp://0.0.0.0:10700";
              microphone = {
                command = "${pkgs.alsa-utils}/bin/arecord -q -D default -r 16000 -c 1 -f S16_LE -t raw";
                autoGain = 5;
                noiseSuppression = 2;
              };
              sound.command = "${pkgs.alsa-utils}/bin/aplay -q -D default -r 22050 -c 1 -f S16_LE -t raw";
              vad.enable = true;
            };
          };

          users = {
            groups.voice = { };
            users = {
              root = {
                initialHashedPassword = "!";
                openssh.authorizedKeys.keys = adminSshKeys;
              };
              thorn = {
                openssh.authorizedKeys.keys = adminSshKeys;
                extraGroups = [
                  "audio"
                  "render"
                  "video"
                ];
              };
              voice = {
                isSystemUser = true;
                group = "voice";
                extraGroups = [ "audio" ];
              };
            };
          };

          environment.systemPackages = with pkgs; [
            alsa-utils
            mangohud
          ];

          systemd = {
            oomd.enable = true;
            services.wyoming-satellite = {
              after = [
                "pipewire.service"
                "wireplumber.service"
              ];
              wants = [
                "pipewire.service"
                "wireplumber.service"
              ];
            };
          };

          zramSwap.enable = true;
          system.stateVersion = "25.05";
        }
      )
    ];
  };
}
