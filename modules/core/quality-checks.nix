{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      source = inputs.self;
    in
    {
      checks = {
        compose-stack = import ../../tests/compose-stack.nix { inherit pkgs lib; };
        shellcheck =
          pkgs.runCommand "thornix-shellcheck-check"
            {
              nativeBuildInputs = [ pkgs.shellcheck ];
            }
            ''
              shellcheck ${source}/scripts/check-fleet
              touch "$out"
            '';

        nixfmt =
          pkgs.runCommand "thornix-nixfmt-check"
            {
              nativeBuildInputs = [
                pkgs.findutils
                pkgs.nixfmt
              ];
            }
            ''
              cd ${source}
              mapfile -d "" files < <(
                find . -type f -name "*.nix" \
                  -not -path "./vendor/*" -print0
              )
              nixfmt --check "''${files[@]}"
              touch "$out"
            '';

        statix =
          pkgs.runCommand "thornix-statix-check"
            {
              nativeBuildInputs = [ pkgs.statix ];
            }
            ''
              cd ${source}
              statix check . --ignore "vendor/**"
              touch "$out"
            '';

        deadnix =
          pkgs.runCommand "thornix-deadnix-check"
            {
              nativeBuildInputs = [ pkgs.deadnix ];
            }
            ''
              cd ${source}
              deadnix --no-lambda-pattern-names --fail --exclude vendor .
              touch "$out"
            '';
      };
    };
}
