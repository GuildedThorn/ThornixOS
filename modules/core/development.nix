{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Keep local formatting and CI's vendor exclusion consistent.
      formatter = pkgs.writeShellApplication {
        name = "thornix-fmt";
        runtimeInputs = [
          pkgs.findutils
          pkgs.nixfmt
        ];
        text = ''
          mapfile -d "" files < <(
            find . -type d \( -name .git -o -name vendor \) -prune -o \
              -type f -name '*.nix' -print0
          )
          exec nixfmt "$@" "''${files[@]}"
        '';
      };

      devShells.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          deadnix
          git
          nixfmt
          shellcheck
          statix
        ];
      };
    };
}
