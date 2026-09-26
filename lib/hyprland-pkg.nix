{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;
  guiutils = inputs.hyprland-guiutils.packages.${system}.default;
  lib = pkgs.lib;

  # Hyprland's pinned rev (e0d9283) requires glaze 7.x, while current
  # nixpkgs provides glaze 8.x. Without the matching package, start/ falls
  # back to a network FetchContent clone during the build.
  glaze = pkgs.glaze.overrideAttrs (old: {
    version = "7.9.0";
    src = pkgs.fetchFromGitHub {
      owner = "stephenberry";
      repo = "glaze";
      tag = "v7.9.0";
      hash = "sha256-vNhxBdGaM70YABfwczvJcAFIYdEGIUGE8Sp2sgkTcaQ=";
    };
  });
  # Hyprland already lists a glaze of its own, so drop that entry and add
  # ours instead of appending. Appending leaves two glaze::glaze targets in
  # buildInputs, and which one CMake resolves depends on link order.
  substituteGlaze = list: [ glaze ] ++ builtins.filter (pkg: (pkg.pname or null) != "glaze") list;
in
inputs.hyprland.packages.${system}.hyprland.overrideAttrs (old: {
  buildInputs = substituteGlaze (old.buildInputs or [ ]);
  # GUI Utils is embedded in Hyprland's wrapper PATH rather than in
  # buildInputs, so define that wrapper without the stale nixpkgs package.
  postInstall = ''
    wrapProgram $out/bin/Hyprland \
      --suffix PATH : ${
        lib.makeBinPath [
          pkgs.binutils
          guiutils
          pkgs.pciutils
          pkgs.pkg-config
        ]
      }
  '';
  passthru = old.passthru or { };
})
