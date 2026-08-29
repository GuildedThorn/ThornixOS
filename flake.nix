{
  description = "NixOS + Home Manager + Makefile DevShell";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    # Stable Raspberry Pi kernel is binary-cached for aarch64 and retains the
    # downstream Google Voice HAT drivers missing from mainline Linux.
    nixpkgs-rpi.url = "github:NixOS/nixpkgs/nixos-25.11";

    openwrt-imagebuilder = {
      url = "github:astro/nix-openwrt-imagebuilder";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jovian-nixos = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    import-tree.url = "github:vic/import-tree";

    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };

    # Pinned just before the src/helpers/Monitor.hpp -> src/output/Monitor.hpp
    # split (2026-06-08) that hyprland-scroll-overview isn't built for yet;
    # bump back to "github:hyprwm/Hyprland" once upstream catches up.
    hyprland = {
      url = "github:hyprwm/Hyprland/a11a718a45c6436abf3d6116618ebb6ae3735148";
      # Without this, Hyprland (and xdg-desktop-portal-hyprland) build against
      # their own pinned nixpkgs' qtbase, which drifts from the qtbase used to
      # build the system's Qt style plugins (e.g. Kvantum). Loading a plugin
      # built against a different qtbase point release into a process linked
      # against another crashes on launch - this is what broke the
      # hyprland-share-picker screenshare dialog.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    hyprland-scroll-overview = {
      url = "github:yayuuu/hyprland-scroll-overview";
      inputs.hyprland.follows = "hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix.url = "github:Gerg-L/spicetify-nix";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    files = {
      url = "github:mightyiam/files";
      # The pinned commit's flakeModules.default deliberately throws,
      # directing consumers to flake = false + a direct file import instead.
      flake = false;
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

    guildedthorn-com.url = "github:GuildedThorn/GuildedThorn.com";

    nix-flatpak.url = "github:gmodena/nix-flatpak/";

    # Source locks for OpenCode's Python integrations. Their own uv.lock files
    # are exported during the Nix build, so both the top-level tools and every
    # transitive Python dependency stay reproducible.
    opencode-jcodemunch-src = {
      url = "github:jgravelle/jcodemunch-mcp/v1.108.279";
      flake = false;
    };

    opencode-serena-src = {
      url = "github:oraios/serena/v1.7.0";
      flake = false;
    };

    opencode-graphify-src = {
      url = "github:Graphify-Labs/graphify/v0.9.43";
      flake = false;
    };

    # Shared source for the FreeCAD addon and OpenCode's MCP bridge.
    opencode-freecad-mcp-src = {
      url = "github:neka-nat/freecad-mcp/0ff3dd380f0deb13677aff4d9a0c94fae326c44a";
      flake = false;
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
