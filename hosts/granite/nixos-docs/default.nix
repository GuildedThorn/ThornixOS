{
  config,
  pkgs,
  inputs,
  ...
}:
let
  # Generated from this exact flake, so the manuals match the nixpkgs revision
  # deployed to the fleet. The upstream NixOS options JSON does not include
  # custom modules; ThornixOS' own thorn.* options are extracted separately
  # from this flake's module sources.
  nixosManual = config.system.build.manual.manualHTML;
  optionsJson = config.system.build.manual.optionsJSON;
  hmManual = inputs.home-manager.packages.${pkgs.system}.docs-html;
  nixpkgsManual = pkgs.nixpkgs-manual;
  thornOptionsJson = inputs.self.packages.${pkgs.system}.thorn-options-json;
  thornOptionsHtml = inputs.self.packages.${pkgs.system}.thorn-options-html;
in
{
  assertions = [
    {
      assertion = config.networking.hostName == "granite";
      message = "the offline NixOS documentation mirror is intended for the granite host";
    }
  ];

  # Served by the same nginx listener that owns /rfc/ and /maps/ on 8083.
  # MITM proxies these paths on wiki.guildedthorn.arpa. Unlike a ZIM these
  # are built from source, so they always match the deployed nixpkgs/HM rev.
  services.nginx.virtualHosts."reference-internal" = {
    locations = {
      "/nixos/" = {
        alias = "${nixosManual}/share/doc/nixos/";
        extraConfig = ''
          index index.html;
        '';
      };
      "= /nixos/options.json" = {
        alias = "${optionsJson}/share/doc/nixos/options.json";
        extraConfig = ''
          default_type application/json;
        '';
      };
      "/home-manager/" = {
        alias = "${hmManual}/share/doc/home-manager/";
        extraConfig = ''
          index index.html;
        '';
      };
      "/nixpkgs/" = {
        alias = "${nixpkgsManual}/share/doc/nixpkgs/";
        extraConfig = ''
          index index.html;
        '';
      };
      "= /thorn-options.json" = {
        alias = "${thornOptionsJson}";
        extraConfig = ''
          default_type application/json;
        '';
      };
      "= /thorn-options" = {
        alias = "${thornOptionsHtml}";
        extraConfig = ''
          default_type text/html;
        '';
      };
      "= /thorn-options/" = {
        alias = "${thornOptionsHtml}";
        extraConfig = ''
          default_type text/html;
        '';
      };
    };
  };
}
