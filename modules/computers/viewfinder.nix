{ config, inputs, ... }:
{
  flake.nixosConfigurations.viewfinder = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-interactive
      inputs.sc0710.nixosModules.default

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
        { pkgs, ... }:
        {
          hardware.sc0710.enable = true;

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

          services.openssh.settings = {
            PasswordAuthentication = true;
            PermitRootLogin = "yes";
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
