{
  description = "NixOS + Home Manager + Makefile DevShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    hyprland.url = "github:hyprwm/Hyprland/v0.54.3";

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

      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
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
      spicetify-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      username =
        if builtins.pathExists ./current-user.lock then
          let
            content = builtins.readFile ./current-user.lock;
          in
          lib.strings.trim (builtins.elemAt (builtins.split "\n" content) 0)
        else
          "thorn";

      hosts =
        if builtins.pathExists ./current-host.lock then
          let
            content = builtins.readFile ./current-host.lock;
          in
          [ (lib.strings.trim (builtins.elemAt (builtins.split "\n" content) 0)) ]
        else if builtins.pathExists (./users + "/${username}/hosts") then
          builtins.attrNames (builtins.readDir (./users + "/${username}/hosts"))
        else
          throw "Host directory not found";
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
              proxmox-nixos
              ;
            host = host;
          };
          modules = [
            hyprland.nixosModules.default
            stylix.nixosModules.stylix
            proxmox-nixos.nixosModules.proxmox-ve
            comin.nixosModules.comin
            sops-nix.nixosModules.sops

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
