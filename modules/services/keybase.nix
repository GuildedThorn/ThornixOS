{
  nixos.modules.services-keybase =
    # After running `nixos-rebuild switch`, `systemctl --user start keybase-gui.service`
    # can be used to start the Keybase GUI.

    { pkgs, ... }:

    {
      services.kbfs = {
        enable = true;
        mountPoint = "%t/kbfs";
        extraFlags = [ "-label %u" ];
      };
      systemd.user.services = {
        keybase.serviceConfig.Slice = "keybase.slice";

        kbfs = {
          environment = {
            KEYBASE_RUN_MODE = "prod";
          };
          serviceConfig.Slice = "keybase.slice";
        };

        keybase-gui = {
          description = "Keybase GUI";
          requires = [
            "keybase.service"
            "kbfs.service"
          ];
          after = [
            "keybase.service"
            "kbfs.service"
          ];
          serviceConfig = {
            ExecStart = "${pkgs.keybase-gui}/share/keybase/Keybase";
            PrivateTmp = true;
            Slice = "keybase.slice";
          };
        };
      };
      environment.systemPackages = with pkgs; [
        keybase
        keybase-gui
      ];
    };
}
