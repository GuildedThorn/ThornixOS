{ inputs, ... }:
let
  adminSshKeys = import ../../hosts/voice-office/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.voice-office = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

      (
        {
          lib,
          pkgs,
          ...
        }:
        let
          rpiKernel = inputs.nixpkgs-rpi.legacyPackages.aarch64-linux.linuxPackages_rpi3.kernel // {
            target = "Image";
          };
        in
        {
          nixpkgs.hostPlatform = "aarch64-linux";

          boot = {
            kernelPackages = pkgs.linuxPackagesFor rpiKernel;
            blacklistedKernelModules = [ "snd_bcm2835" ];
            initrd = {
              includeDefaultModules = false;
              availableKernelModules = lib.mkForce [
                "mmc_block"
                "sdhci"
                "sdhci_iproc"
              ];
            };
            supportedFilesystems.zfs = lib.mkForce false;
            zfs.forceImportRoot = false;
          };
          system.boot.loader.kernelFile = "Image";

          hardware = {
            enableRedistributableFirmware = true;
            deviceTree = {
              enable = true;
              filter = "bcm2710-rpi-3-b-plus.dtb";
              name = "broadcom/bcm2710-rpi-3-b-plus.dtb";
              overlays = [
                {
                  name = "googlevoicehat-soundcard";
                  dtsFile = "${inputs.self}/hosts/voice-office/googlevoicehat-soundcard-overlay.dts";
                }
              ];
            };
          };

          networking = {
            hostName = "voice-office";
            domain = "guildedthorn.arpa";
            useDHCP = lib.mkDefault true;
            firewall = {
              enable = true;
              extraCommands = ''
                iptables -A nixos-fw -p tcp -s 172.16.25.2 --dport 10700 -j nixos-fw-accept
              '';
            };
          };

          services = {
            avahi = {
              enable = true;
              nssmdns4 = true;
              publish = {
                enable = true;
                addresses = true;
                workstation = true;
              };
            };
            openssh = {
              enable = true;
              openFirewall = true;
              settings = {
                KbdInteractiveAuthentication = false;
                PasswordAuthentication = false;
                PermitRootLogin = "prohibit-password";
              };
            };
            wyoming.satellite = {
              enable = true;
              user = "voice";
              group = "voice";
              name = "Office Voice";
              area = "Office";
              uri = "tcp://0.0.0.0:10700";
              microphone = {
                command = "arecord -q -D plughw:CARD=sndrpigooglevoi,DEV=0 -r 16000 -c 1 -f S16_LE -t raw";
                autoGain = 5;
                noiseSuppression = 2;
              };
              sound.command = "aplay -q -D plughw:CARD=sndrpigooglevoi,DEV=0 -r 22050 -c 1 -f S16_LE -t raw";
              # Silero VAD is currently broken on aarch64 in nixpkgs.
              vad.enable = false;
            };
          };

          users = {
            groups.voice = { };
            users = {
              root = {
                initialHashedPassword = "!";
                openssh.authorizedKeys.keys = adminSshKeys;
              };
              voice = {
                isSystemUser = true;
                group = "voice";
                extraGroups = [ "audio" ];
              };
            };
          };

          nix.settings = {
            experimental-features = [
              "nix-command"
              "flakes"
            ];
            extra-substituters = [ "https://guildedthorn.cachix.org" ];
            extra-trusted-public-keys = [
              "guildedthorn.cachix.org-1:xBlJbEHPcUXnI4D261WqjlM1/WgPqn2yWH6c5BMOxHc="
            ];
          };

          environment.systemPackages = with pkgs; [
            alsa-utils
            git
          ];

          time.timeZone = "America/Chicago";
          i18n.defaultLocale = "en_US.UTF-8";
          sdImage.compressImage = true;
          system.stateVersion = "25.05";
        }
      )
    ];
  };
}
