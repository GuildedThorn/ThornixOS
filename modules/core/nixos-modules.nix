{ lib, ... }:
{
  options.nixos.modules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.deferredModule;
    default = { };
  };
}
