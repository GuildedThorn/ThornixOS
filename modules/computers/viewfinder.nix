{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/viewfinder/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.viewfinder = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-interactive
      inputs.sc0710.nixosModules.default
      config.nixos.modules.hardware-sc0710-firmware

      config.nixos.modules.desktop-hyprland
      config.nixos.modules.processor-amd
      config.nixos.modules.graphics-nvidia

      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-obs
      config.nixos.modules.services-ssh

      config.nixos.modules.hardware-viewfinder
      "${inputs.self}/hosts/viewfinder/disko.nix"
      "${inputs.self}/hosts/viewfinder/networking.nix"
      "${inputs.self}/hosts/viewfinder/secrets.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/viewfinder/home.nix"; }

      (
        {
          config,
          pkgs,
          lib,
          ...
        }:
        {
          hardware.sc0710.enable = true;

          # sc0710 supports kernels up to 7.0, and 7.0 is EOL in nixpkgs, so
          # pin the boot kernel to 6.18 (same line the installer boots).
          boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_18;

          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
          boot.initrd.systemd.enable = true;

          boot.extraModulePackages = with config.boot.kernelPackages; [
            nvidia_x11
          ];

          environment.systemPackages = with pkgs; [
            v4l-utils
            ffmpeg
            obs-studio

            ghostty
          ];

          users = {
            users = {
              root = {
                initialHashedPassword = "!";
                openssh.authorizedKeys.keys = adminSshKeys;
              };
              thorn = {
                openssh.authorizedKeys.keys = adminSshKeys;
              };
            };
          };

          zramSwap = {
            enable = true;
            memoryPercent = 25;
          };

          security.rtkit.enable = true;

          services.earlyoom.enable = true;
          services.fwupd.enable = true;
        }
      )
    ];
  };
}
