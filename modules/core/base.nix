{ inputs, ... }:
{
  nixos.modules.base =
    { lib, pkgs, ... }:
    {
      imports = [
        inputs.lanzaboote.nixosModules.lanzaboote
        inputs.disko.nixosModules.disko
        inputs.hyprland.nixosModules.default
        inputs.stylix.nixosModules.stylix
        inputs.proxmox-nixos.nixosModules.proxmox-ve
        inputs.comin.nixosModules.comin
        inputs.sops-nix.nixosModules.sops
        inputs.scroll-flake.nixosModules.default
        inputs.sc0710.nixosModules.default
        inputs.nix-flatpak.nixosModules.nix-flatpak
      ];

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operators"
        ];

        # CI uploads every successful host closure to this public cache.
        # Consume those artifacts on the fleet instead of rebuilding the
        # same packages locally during each comin deployment.
        # The LAN Harmonia cache is authoritative for this fleet's closures;
        # Cachix remains a fallback for packages not yet mirrored.
        extra-substituters = [
          "https://cache.guildedthorn.arpa"
          "https://guildedthorn.cachix.org"
        ];
        extra-trusted-public-keys = [
          "cache.guildedthorn.arpa-1:FiC7ATzV0EBfOYZU/L53SqLG1bwtpbeSa3Ly9vz84/w="
          "guildedthorn.cachix.org-1:xBlJbEHPcUXnI4D261WqjlM1/WgPqn2yWH6c5BMOxHc="
        ];
        connect-timeout = 5;
      };

      services.resolved.enable = false;

      programs.nh = {
        enable = true;
        clean.enable = true;
        clean.extraArgs = "--keep-since 4d --keep 3";
        flake = "/etc/nixos";
      };

      environment.systemPackages = with pkgs; [
        git
        forgejo-cli
        gh
        glab
        gnumake

        bmon
        iftop
        iperf3

        nixfmt
        nixfmt-tree

        sbctl

        sops
        ssh-to-age
      ];

      # Allow unfree packages
      hardware.enableAllFirmware = true;
      hardware.enableRedistributableFirmware = true;
      nixpkgs.config.allowUnfree = true;

      boot.kernelPackages = pkgs.linuxPackages_latest;
      # Compatibility defaults for existing installations; not the package release.
      system.stateVersion = "25.05";
    };
}
