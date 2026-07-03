{ inputs, ... }:
{
  nixos.modules.base =
    { pkgs, ... }:
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

      users.users.thorn.isNormalUser = true;

      # -------------------------
      # Experimental Features
      # -------------------------
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];

      # -------------------------
      # DNS Resolver
      # -------------------------
      services.resolved.enable = false;

      # -------------------------
      # Nix Helper
      # -------------------------
      programs.nh = {
        enable = true;
        clean.enable = true;
        clean.extraArgs = "--keep-since 4d --keep 3";
        flake = "/etc/nixos"; # sets NH_OS_FLAKE variable for you
      };

      # List packages installed in system profile. To search, run:
      # $ nix search <package>
      environment.systemPackages = with pkgs; [
        git
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

      # This value determines the NixOS release from which the default
      # settings for stateful data, like file locations and database versions
      # on your system were taken. It's perfectly fine and recommended to leave
      # this value at the release version of the first install of this system.
      # Before changing this value read the documentation for this option
      # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
      boot.kernelPackages = pkgs.linuxPackages_latest;
      system.stateVersion = "25.05"; # Did you read the comment?
    };
}
