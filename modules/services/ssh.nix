{
  nixos.modules.services-ssh =
    { ... }:

    {

      programs.ssh.startAgent = true;
      services.openssh.enable = true;

    };
}
