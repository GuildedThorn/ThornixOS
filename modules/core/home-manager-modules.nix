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
