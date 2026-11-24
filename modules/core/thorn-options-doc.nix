{
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      extractor = "${inputs.self}/lib/thorn-options-extract.py";

      commonMeta = {
        nativeBuildInputs = [ pkgs.python3 ];
      };

      thornOptionsJson = pkgs.runCommand "thorn-options.json" commonMeta ''
        ${pkgs.python3.interpreter} ${extractor} ${inputs.self} json > $out
      '';

      # A directory with index.html lets nginx serve /thorn-options/ via a
      # normal prefix location. Aliasing a file from a trailing-slash location
      # makes nginx look for <file>/index.html and return 500.
      thornOptionsHtml = pkgs.runCommand "thorn-options-html" commonMeta ''
        mkdir -p $out
        ${pkgs.python3.interpreter} ${extractor} ${inputs.self} html > $out/index.html
      '';
    in
    {
      packages.thorn-options-json = thornOptionsJson;
      packages.thorn-options-html = thornOptionsHtml;
    };
}
