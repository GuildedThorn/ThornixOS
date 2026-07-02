{
  nixos.modules."services-fingerprint" =
    {
      pkgs,
      ...
    }:

    {

      services.fprintd.enable = true;
      services.fprintd.tod.enable = false;
      services.fprintd.tod.driver = pkgs.libfprint-2-tod1-vfs0090;

      security.pam.services.login.fprintAuth = true;
      security.pam.services.sudo.fprintAuth = true;
    };
}
