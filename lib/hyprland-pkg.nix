{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;

  # Hyprland's pinned rev (e0d9283) buildInputs glaze under strictDeps, so
  # CMake's find_package(glaze 7...<8) never sees it; start/ falls back to
  # FetchContent, which git-clones glaze v7.2.0 during configure. The Nix
  # sandbox has neither git nor network, so configure dies there. Override the
  # FetchContent source dir with a store-fetched glaze tarball instead.
  glazeSrc = pkgs.fetchFromGitHub {
    owner = "stephenberry";
    repo = "glaze";
    rev = "v7.2.0";
    hash = "sha256-f3NVRi3SXKo42hn0WCw7JsOK3EkdOVJIcuzhPorKjFY=";
  };
in
inputs.hyprland.packages.${system}.hyprland.overrideAttrs (old: {
  cmakeFlags = old.cmakeFlags ++ [ "-DFETCHCONTENT_SOURCE_DIR_GLAZE=${glazeSrc}" ];
})
