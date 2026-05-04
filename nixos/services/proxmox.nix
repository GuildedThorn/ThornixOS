{
  lib,
  system,
  proxmox-nixos,
  ...
}:

{

  services.openssh.settings.AcceptEnv = lib.mkForce [
    "LANG"
    "LC_*"
  ];

  services.proxmox-ve = {
    enable = true;
  };

  nixpkgs.overlays = [
    proxmox-nixos.overlays.${system}
  ];
}
