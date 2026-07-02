{
  nixos.modules."services-obs" =
    { config, pkgs, ... }:

    {

      programs.obs-studio = {
        enable = true;

        plugins = with pkgs.obs-studio-plugins; [
          wlrobs
          obs-backgroundremoval
          obs-pipewire-audio-capture

          #optional AMD hardware acceleration
          obs-vaapi

          obs-gstreamer

        ];
      };

      boot.extraModulePackages = with config.boot.kernelPackages; [
        v4l2loopback
      ];

      boot.extraModprobeConfig = ''
        options v4l2loopback devices=1 video_nr=10 card_label="OBS Cam" exclusive_caps=1 max_buffers=2
      '';

    };
}
