{ config, inputs, ... }:
{
  flake.nixosConfigurations.mac = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.desktop-hyprland
      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-amd

      config.nixos.modules.services-clamav
      config.nixos.modules.services-proxmox
      config.nixos.modules.services-ssh

      "${inputs.self}/hosts/mac/disko.nix"
      "${inputs.self}/hosts/mac/networking.nix"
      "${inputs.self}/hosts/mac/secrets.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/mac/home.nix"; }

      (
        { lib, modulesPath, ... }:
        {
          imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

          # Hardware discovered from the running Proxmox installation.
          boot = {
            initrd = {
              availableKernelModules = [
                "ahci"
                "ehci_pci"
                "uhci_hcd"
                "usb_storage"
                "sd_mod"
                "sr_mod"
              ];
              systemd.enable = true;
            };
            kernelModules = [ "kvm-intel" ];
            kernelParams = [
              "intel_iommu=on"
              "iommu=pt"
            ];
            loader = {
              systemd-boot.enable = true;
              efi.canTouchEfiVariables = true;
            };
          };

          nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

          # Tahiti (Southern Islands / HD 7950) needs the legacy amdgpu
          # switch; otherwise the configured amdgpu desktop has no driver.
          hardware.amdgpu.legacySupport.enable = true;

          services.proxmox-ve = {
            ipAddress = "172.16.25.3";
            bridges = [
              "vmbr0"
              "vmbr1"
              "vmbr2"
            ];
          };

          # Keep a key-only recovery path after nixos-anywhere reboots into
          # the freshly installed system.
          services.openssh.settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
          };
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+iFLtqnhkscz2qLK45nJVmGZIbQvIeIuW8tenAjX2p thorn@workstation"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIESh83q74VIIDGsHLvu6a1ptpmkae739Nz8SshW58eWY thorn"
          ];
        }
      )
    ];
  };
}
