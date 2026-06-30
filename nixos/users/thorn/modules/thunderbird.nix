{
  config,
  lib,
  ...
}:
let
  cfg = config.thorn.programs.thunderbird;
in
{
  options.thorn.programs.thunderbird.enable =
    lib.mkEnableOption "Thorn's ThunderBird Home Manager configuration";

  config = lib.mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      policies = {
        DisableTelemetry = true;
        DisableAppUpdate = true;
      };
    };
  };
}
