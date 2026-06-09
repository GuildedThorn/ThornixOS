{
  inputs,
  ...
}:
{

  imports = [
    ./networking.nix

    "${inputs.self}/desktop/xfce+i3.nix"

    "${inputs.self}/services/audio.nix"
    "${inputs.self}/services/clamav.nix"
    "${inputs.self}/services/ssh.nix"
  ];

  home-manager.users.thorn = import ./home.nix;
}
