{ inputs, ... }:
{
  nixos.modules.services-proxmox =
    {
      lib,
      config,
      pkgs,
      ...
    }:

    {

      # The `qm` binary can resolve to the pve-ha-manager wrapper, which does
      # not include cdrkit in PATH when generating cloud-init images.
      environment.systemPackages = [ pkgs.cdrkit ];

      # pve-manager ships notification templates below /usr/share, but the
      # NixOS profile does not link that subtree by default.  Without these
      # templates Proxmox's notification test fails before SMTP is attempted.
      environment.pathsToLink = [ "/usr/share/pve-manager" ];

      services.openssh.settings.AcceptEnv = lib.mkForce [
        "LANG"
        "LC_*"
      ];

      services.proxmox-ve = {
        enable = true;
        openFirewall = false;
      };

      nixpkgs.overlays = [
        inputs.proxmox-nixos.overlays.${config.nixpkgs.system}
      ];
    };
}
