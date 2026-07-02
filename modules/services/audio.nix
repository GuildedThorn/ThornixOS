{
  nixos.modules.services-audio =
    { pkgs, ... }:
    {

      services.pipewire = {
        enable = true;
        pulse.enable = true;
        jack.enable = true;
        alsa = {
          enable = true;
          support32Bit = true;
        };
      };

      services.pipewire.wireplumber.enable = true;

      security.rtkit.enable = true;

      services.pulseaudio.enable = false;

      environment.systemPackages = with pkgs; [
        pavucontrol
      ];
    };
}
