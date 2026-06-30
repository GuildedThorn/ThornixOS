{
  description = "NixOS + Home Manager + Makefile DevShell";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";

    hyprland.url = "github:hyprwm/Hyprland";

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    spicetify-nix.url = "github:Gerg-L/spicetify-nix";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    astal.url = "github:aylur/astal";

    ags.url = "github:aylur/ags";

    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sc0710.url = "github:Nakildias/sc0710";

    yazi.url = "github:sxyazi/yazi";

    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";

    scroll-flake = {
      url = "github:Diax170/scroll-flake";
      inputs.nixpkgs.follows = "nixpkgs"; # this assumes nixos unstable
    };
    awww.url = "git+https://codeberg.org/LGFae/awww";

    nix-flatpak.url = "github:gmodena/nix-flatpak/";
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      hyprland,
      comin,
      proxmox-nixos,
      stylix,
      nixvim,
      sops-nix,
      lanzaboote,
      disko,
      yazi,
      spicetify-nix,
      scroll-flake,
      awww,
      sc0710,
      nix-flatpak,
      ...
    }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      username = "thorn";
      hosts = builtins.attrNames (builtins.readDir (./users + "/${username}/hosts"));
    in
    {
      nixosConfigurations = lib.genAttrs hosts (
        host:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              inputs
              system
              username
              hyprland
              comin
              spicetify-nix
              nixvim
              sops-nix
              lanzaboote
              disko
              yazi
              nix-flatpak
              scroll-flake
              awww
              sc0710
              proxmox-nixos
              ;
            host = host;
          };
          modules = [
            lanzaboote.nixosModules.lanzaboote
            disko.nixosModules.disko
            hyprland.nixosModules.default
            stylix.nixosModules.stylix
            proxmox-nixos.nixosModules.proxmox-ve
            comin.nixosModules.comin
            sops-nix.nixosModules.sops
            scroll-flake.nixosModules.default
            sc0710.nixosModules.default
            nix-flatpak.nixosModules.nix-flatpak

            ./configuration.nix

            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useUserPackages = true;
                backupFileExtension = "backup";
                extraSpecialArgs = { inherit inputs; };
              };
            }
          ];
        }
      );
    };
}
