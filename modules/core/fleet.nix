{
  config,
  inputs,
  lib,
  ...
}:
let
  inventory = import ../../hosts/inventory.nix;
  configurations = config.flake.nixosConfigurations;
  inventoryNames = lib.sort builtins.lessThan (builtins.attrNames inventory);
  productionHosts = lib.filter (name: inventory.${name}.production) inventoryNames;
  validationHosts = lib.filter (name: !inventory.${name}.production) inventoryNames;
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  # NixOS system derivations carry a large evaluated module graph in
  # passthru attributes. Strip everything Hydra does not need so its single
  # evaluator worker can release that graph between fleet jobs.
  systemJob = name: pkgs.lib.hydraJob configurations.${name}.config.system.build.toplevel;
  productionJobs = lib.genAttrs productionHosts systemJob;
  validationJobs = lib.genAttrs validationHosts systemJob;
  # A clean Git/GitHub flake exposes its exact source revision. Stamp that
  # revision into the aggregate's store name so the promoter can identify a
  # completed Hydra result without re-evaluating the entire fleet. Local dirty
  # evaluations deliberately use a non-promotable name.
  revision = inputs.self.rev or "uncommitted";
in
{
  # Machine-readable outputs are consumed by GitHub's bootstrap CI and make
  # the same membership available to future tooling without parsing Nix
  # source text.
  flake = {
    thornixFleet = inventory;
    thornixRevision = revision;
    productionHosts = productionHosts;
    validationHosts = validationHosts;

    # Hydra builds every declared configuration. Production promotion checks
    # the individual production jobs through Hydra's local API instead of
    # evaluating one monolithic aggregate, which would retain the whole fleet
    # module graph in a single evaluator process.
    hydraJobs = {
      production = productionJobs;
      validation = validationJobs;
    };
  };
}
