{ inputs, ... }:
{
  # Self-contained: the nixvim fragments below configure programs.nixvim,
  # so anything consuming homeManager.modules.nixvim standalone also gets
  # the upstream module.
  homeManager.modules.nixvim = {
    imports = [ inputs.nixvim.homeModules.nixvim ];
  };
}
