{
  config,
  lib,
  inputs,
  ...
}:
{
  options.homeManager.modules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.deferredModule;
    default = { };
  };

  # Standalone Home Manager profiles are assembled by several modules (one
  # per target machine), so declare the flake output instead of assigning the
  # whole attribute set from a single file.
  options.flake.homeConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = { };
  };

  config = {
    # Expose the composed module for tooling (notably nixd option discovery)
    # and for consumers that want the same Home Manager setup standalone.
    flake.homeManagerModules.thorn = config.homeManager.modules.thorn;

    nixos.modules.home-manager-base = {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useUserPackages = true;
        backupFileExtension = "backup";
      };
    };
  };
}
