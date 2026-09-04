{ config, inputs, ... }:
let
  fleet = import ../../hosts/inventory.nix;
in
{
  flake.nixosConfigurations.mac = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-interactive

      config.nixos.modules.desktop-xfce-i3
      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-amd

      config.nixos.modules.services-canary
      config.nixos.modules.services-clamav
      config.nixos.modules.services-ksm
      config.nixos.modules.services-proxmox
      config.nixos.modules.services-proxmox-provisioner
      config.nixos.modules.services-ssh
      config.nixos.modules.services-zeek

      "${inputs.self}/hosts/mac/disko.nix"
      "${inputs.self}/hosts/mac/networking.nix"
      "${inputs.self}/hosts/mac/secrets.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/mac/home.nix"; }

      (
        {
          lib,
          modulesPath,
          pkgs,
          ...
        }:
        let
          topologyFleet = lib.filterAttrs (
            _: host: host.address != null && lib.hasPrefix "172.16.25." host.address
          ) fleet;
          managedTopologyHosts = builtins.listToAttrs (
            lib.mapAttrsToList (name: host: {
              name = host.address;
              value = {
                title = name;
                inherit (host) role;
              };
            }) topologyFleet
          );
        in
        {
          imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

          # This machine is now the always-on hypervisor. Processes spawned
          # through pveproxy/pvedaemon have no loginuid, so the workstation
          # default would miss execution after a service compromise.
          thorn.audit.execScope = "all";

          # The hypervisor ships its journal and audit stream to the SOC, so
          # its local copies are a recovery window rather than the archive.
          # Bound both stores and collect dead Nix closures daily; VM images
          # should be the only data allowed to dominate this filesystem.
          programs.nh.clean.dates = "daily";
          security.auditd.settings = {
            max_log_file = 50;
            num_logs = 6;
          };
          services.journald.extraConfig = ''
            SystemMaxUse=1G
            RuntimeMaxUse=128M
            MaxRetentionSec=7day
          '';

          systemd.tmpfiles.rules = [
            "d /var/backup/proxmox 0700 root root -"
          ];

          # Guest application state is protected on each VM. Preserve the
          # hypervisor's own pmxcfs database separately so bridge, storage,
          # ACL, and guest definitions can be recovered without a raw host
          # image. SQLite's online backup API produces a consistent copy.
          thorn.backup = {
            enable = true;
            schedule = "*-*-* 02:00:00";
            # Archive any intentionally created full-VM dumps off-host before
            # local retention removes them. Guest application state remains
            # protected independently by each VM's own daily backup.
            paths = [
              "/var/backup/proxmox"
              "/var/lib/vz/dump"
            ];
            prepareCommand = ''
              temporary=/var/backup/proxmox/config.db.new
              ${pkgs.sqlite}/bin/sqlite3 /var/lib/pve-cluster/config.db \
                ".backup '$temporary'"
              ${pkgs.coreutils}/bin/chmod 0600 "$temporary"
              ${pkgs.coreutils}/bin/mv -T "$temporary" \
                /var/backup/proxmox/config.db
            '';
            restorePaths = [ "/var/backup/proxmox/config.db" ];
            restoreValidationCommand = ''
              ${pkgs.sqlite}/bin/sqlite3 \
                "$RESTORE_ROOT/var/backup/proxmox/config.db" \
                'PRAGMA integrity_check;' \
                | ${pkgs.gnugrep}/bin/grep --fixed-strings --line-regexp ok >/dev/null
            '';
          };

          # Full VM dumps are large and only supplement the authoritative
          # per-guest backups. Remove aged local copies only after restic has
          # successfully archived the dump directory off-host.
          systemd.services."restic-backups-mac".unitConfig.OnSuccess = [
            "proxmox-vzdump-retention.service"
          ];
          systemd.services.proxmox-vzdump-retention = {
            description = "Remove off-host archived Proxmox VM dumps";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = pkgs.writeShellScript "proxmox-vzdump-retention" ''
                set -o errexit -o nounset -o pipefail
                ${pkgs.findutils}/bin/find /var/lib/vz/dump \
                  -maxdepth 1 -type f -mtime +14 \
                  \( -name 'vzdump-*.vma.zst' \
                     -o -name 'vzdump-*.vma.zst.sha256' \) \
                  -delete
              '';
            };
          };

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
                "172.16.25.4" = {
                  title = "TrueNAS";
                  role = "storage";
                };
              }
              // managedTopologyHosts;
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

          # All guests are single-tenant NixOS workloads on this physical
          # host. Deduplicate their identical anonymous pages with a bounded,
          # adaptive scan instead of overcommitting RAM blindly. KSM cannot
          # share memory with a different physical host.
          thorn.ksm = {
            enable = true;
            advisor = {
              maxCpuPercent = 10;
              targetScanTimeSeconds = 600;
            };
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
