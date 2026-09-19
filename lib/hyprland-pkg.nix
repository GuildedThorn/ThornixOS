{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;

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
in
inputs.hyprland.packages.${system}.hyprland.overrideAttrs (old: {
  buildInputs = (old.buildInputs or [ ]) ++ [ glaze ];
})
