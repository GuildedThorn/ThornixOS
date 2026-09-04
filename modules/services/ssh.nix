{
  nixos.modules.services-ssh =
    { ... }:

    {

      services.openssh = {
        enable = true;
        openFirewall = false;
        settings = {
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;
        };
      };

    };
}
