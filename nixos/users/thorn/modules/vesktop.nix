{
  config,
  lib,
  ...
}:
let
  cfg = config.thorn.programs.vesktop;
in
{
  options.thorn.programs.vesktop.enable =
    lib.mkEnableOption "Thorn's Vesktop Home Manager configuration";

  config = lib.mkIf cfg.enable {
    programs.vesktop = {
      enable = true;
      settings = {
        arRPC = true;
        hardwareAcceleration = true;
        minimizeToTray = true;
        checkUpdates = true;
        tray = true;
        discordBranch = "canary";
      };

      vencord = {
        settings = {
          autoUpdate = true;
          autoUpdateNotification = true;
          notifyAboutUpdates = false;

          plugins = {
            MessageLogger = {
              enabled = true;
              ignoreSelf = true;
            };
            FixSpotifyEmbeds.enabled = true;
            SpotifyControls.enabled = true;
            SpotifyCrack.enabled = true;
            SilentTyping.enabled = true;
            USRGB.enabled = true;
            ValidUser.enabled = true;
            YutubeAdBlock.enabled = true;
            ShowHiddenChannels.enabled = true;
            PlatformIndicators.enabled = true;
            Translate.enabled = true;
            FakeNitro.enabled = true;
          };
        };
      };
    };
  };
}
