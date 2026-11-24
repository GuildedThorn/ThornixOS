{
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      extractor = "${inputs.self}/lib/thorn-options-extract.py";

      mkDoc =
        name: mode:
        pkgs.runCommand name
          {
            nativeBuildInputs = [ pkgs.python3 ];
            meta.description = "ThornixOS thorn.* options in ${mode} format";
          }
          ''
            ${pkgs.python3.interpreter} ${extractor} ${inputs.self} ${mode} > $out
          '';
    in
    {
      packages.thorn-options-json = mkDoc "thorn-options.json" "json";
      packages.thorn-options-html = mkDoc "thorn-options.html" "html";
    };
}
