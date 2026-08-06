{ config, inputs, ... }:
{
  flake.nixosConfigurations.mac = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.desktop-xfce-i3
      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-amd

      config.nixos.modules.services-canary
      config.nixos.modules.services-clamav
      config.nixos.modules.services-proxmox
      config.nixos.modules.services-proxmox-provisioner
      config.nixos.modules.services-ssh
      config.nixos.modules.services-zeek

      "${inputs.self}/hosts/mac/disko.nix"
      "${inputs.self}/hosts/mac/networking.nix"
      "${inputs.self}/hosts/mac/secrets.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/mac/home.nix"; }

      (
        { lib, modulesPath, ... }:
        {
          imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

          # This machine is now the always-on hypervisor. Processes spawned
          # through pveproxy/pvedaemon have no loginuid, so the workstation
          # default would miss execution after a service compromise.
          thorn.audit.execScope = "all";

          # vmbr0 is the point at which Proxmox guest-to-guest and
          # guest-to-physical traffic converges. The bridge capture was
          # verified live with websites (172.16.25.50) talking directly to
          # soc (172.16.25.51), with no kernel packet drops.
          thorn.zeek = {
            enable = true;
            interface = "vmbr0";
            localNetworks = [ "172.16.25.0/24" ];
            tlsTrustAnchor = "${inputs.self}/certs/ThornCloud_CA.crt";
            # Do not let Zeek observe the HTTP requests Alloy creates while
            # shipping Zeek's own logs. Excluding both directions of only
            # this host-to-Loki flow prevents recursion without hiding other
            # hosts' use of Loki or other traffic to the SOC.
            captureFilter = "not (host 172.16.25.3 and host 172.16.25.51 and tcp port 3100)";

            # Five-minute active-flow graph, rendered every five seconds and
            # exposed through the existing SOC-only node_exporter listener.
            # Unknown OPT1 IPs remain individual nodes. Public and non-OPT1
            # private peers are collapsed upstream so an Internet scan cannot
            # poison Prometheus with unbounded label cardinality.
            topology = {
              enable = true;
              knownHosts = {
                "172.16.25.1" = {
                  title = "pfSense";
                  role = "firewall";
                };
                "172.16.25.2" = {
                  title = "mitm";
                  role = "lab";
                };
                "172.16.25.3" = {
                  title = "mac";
                  role = "hypervisor";
                };
                "172.16.25.4" = {
                  title = "TrueNAS";
                  role = "storage";
                };
                "172.16.25.50" = {
                  title = "websites";
                  role = "web";
                };
                "172.16.25.51" = {
                  title = "soc";
                  role = "siem";
                };
                "172.16.25.52" = {
                  title = "identity";
                  role = "identity";
                };
                "172.16.25.53" = {
                  title = "pixie";
                  role = "provisioning";
                };
              };
            };
          };

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
