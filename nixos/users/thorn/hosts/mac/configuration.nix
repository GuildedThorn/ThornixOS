{
  config,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./networking.nix
    ./disko.nix

    "${inputs.self}/desktop/hyprland.nix"
    "${inputs.self}/processor/intel.nix"
    "${inputs.self}/graphics/amd.nix"

    "${inputs.self}/services/clamav.nix"
    "${inputs.self}/services/proxmox.nix"
    "${inputs.self}/services/ssh.nix"
  ];

}
