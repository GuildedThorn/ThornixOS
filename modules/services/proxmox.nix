{
  nixos.modules."services-proxmox" =
    {
      lib,
      config,
      inputs,
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
        inputs.proxmox-nixos.overlays.${config.nixpkgs.system}
      ];
    };
}
