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
  productionJobs = lib.genAttrs productionHosts (
    name: configurations.${name}.config.system.build.toplevel
  );
  validationJobs = lib.genAttrs validationHosts (
    name: configurations.${name}.config.system.build.toplevel
  );
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
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

    # Hydra builds every declared configuration, but only production jobs are
    # constituents of the release gate. Templates and tests therefore keep
    # compiling without blocking a fleet deployment.
    hydraJobs = {
      production = productionJobs;
      validation = validationJobs;
      required = pkgs.releaseTools.aggregate {
        name = "thornixos-production-required-${revision}";
        constituents = builtins.attrValues productionJobs;
        meta.description = "Every production ThornixOS host built successfully";
      };
    };
  };
}
