{ inputs, ... }:
{
  nixos.modules.services-proxmox-provisioner =
    { lib, pkgs, ... }:
    let
      hostsDirectory = ../../hosts;
      hostEntries = builtins.readDir hostsDirectory;
      profileNames = lib.sort builtins.lessThan (
        lib.filter (
          name:
          hostEntries.${name} == "directory" && builtins.pathExists (hostsDirectory + "/${name}/proxmox.nix")
        ) (builtins.attrNames hostEntries)
      );
      rawProfiles = lib.genAttrs profileNames (name: import (hostsDirectory + "/${name}/proxmox.nix"));

      normalizeProfile =
        name: profile:
        let
          resources = profile.resources;
          readiness = profile.readiness or { };
          httpChecks = map (check: {
            inherit (check) url;
            caCertificate = if check ? caCertificate then toString check.caCertificate else "";
            resolve = check.resolve or "";
            expectPattern = check.expectPattern or "";
          }) (readiness.httpChecks or [ ]);
        in
        assert lib.assertMsg (
          builtins.match "[a-z][a-z0-9-]*" name != null
        ) "provision profile '$name' must be a lowercase hostname";
        assert lib.assertMsg (
          builtins.isInt profile.vmid && profile.vmid > 0
        ) "provision profile '$name' needs a positive integer vmid";
        assert lib.assertMsg (
          builtins.isList profile.adminSshKeys && profile.adminSshKeys != [ ]
        ) "provision profile '$name' needs at least one admin SSH key";
        assert lib.assertMsg (
          builtins.stringLength profile.isoLabel <= 32
        ) "provision profile '$name' has an ISO label longer than 32 characters";
        assert lib.assertMsg (
          builtins.stringLength profile.diskSerial <= 20
        ) "provision profile '$name' has a disk serial longer than 20 characters";
        assert lib.assertMsg (
          builtins.isInt resources.cores && resources.cores > 0
        ) "provision profile '$name' needs at least one CPU core";
        assert lib.assertMsg (
          builtins.isInt resources.memoryMiB && resources.memoryMiB >= 512
        ) "provision profile '$name' needs at least 512 MiB RAM";
        assert lib.assertMsg (
          builtins.isInt resources.diskGiB && resources.diskGiB >= 4
        ) "provision profile '$name' needs a disk of at least 4 GiB";
        {
          inherit name;
          inherit (profile)
            address
            adminSshKeys
            diskSerial
            isoLabel
            vmid
            ;
          bridge = profile.bridge or "vmbr0";
          storage = profile.storage or "local";
          gateway = profile.gateway or "172.16.25.1";
          prefixLength = profile.prefixLength or 24;
          nameservers =
            profile.nameservers or [
              "172.16.25.1"
              "1.1.1.1"
            ];
          inherit (resources) cores memoryMiB diskGiB;
          minimumDiskGiB = resources.diskGiB - 1;
          maximumDiskGiB = resources.diskGiB + 1;
          minimumFreeGiB = resources.diskGiB + 5;
          isoVolume = "local:iso/thornix-${name}-installer.iso";
          installerProfile = "${name}/v1";
          defaultFlake = "github:GuildedThorn/ThornixOS/deploy-${name}#${name}";
          readiness = {
            displayName = readiness.displayName or name;
            label = readiness.label or "${name} services";
            units = readiness.units or [ ];
            inherit httpChecks;
            tftpChecks = readiness.tftpChecks or [ ];
            readyLines = readiness.readyLines or [ ];
          };
        };

      normalizedProfiles = lib.mapAttrs normalizeProfile rawProfiles;
      profileList = builtins.attrValues normalizedProfiles;
      vmids = map (profile: profile.vmid) profileList;
      addresses = map (profile: profile.address) profileList;
      diskSerials = map (profile: profile.diskSerial) profileList;
      validatedProfiles =
        assert lib.assertMsg (
          profileNames != [ ]
        ) "thornix-provision found no hosts/*/proxmox.nix profile files";
        assert lib.assertMsg (
          builtins.length (lib.unique vmids) == builtins.length vmids
        ) "thornix-provision profiles must have unique Proxmox VMIDs";
        assert lib.assertMsg (
          builtins.length (lib.unique addresses) == builtins.length addresses
        ) "thornix-provision profiles must have unique IP addresses";
        assert lib.assertMsg (
          builtins.length (lib.unique diskSerials) == builtins.length diskSerials
        ) "thornix-provision profiles must have unique disk serials";
        normalizedProfiles;

      mkInstaller =
        profile:
        inputs.nixpkgs.lib.nixosSystem {
          system = pkgs.stdenv.hostPlatform.system;
          modules = [
            "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            (
              { lib, ... }:
              {
                isoImage.volumeID = profile.isoLabel;

                # Every managed VM has one virtio NIC. A stable interface
                # name lets its installer use the final static address with
                # no DHCP or cloud-init dependency.
                boot.kernelParams = [ "net.ifnames=0" ];
                networking = {
                  hostName = "thornix-${profile.name}-installer";
                  enableIPv6 = false;
                  useDHCP = lib.mkForce false;
                  networkmanager.enable = lib.mkForce false;
                  interfaces.eth0 = {
                    useDHCP = false;
                    ipv4.addresses = [
                      {
                        address = profile.address;
                        prefixLength = profile.prefixLength;
                      }
                    ];
                  };
                  defaultGateway = {
                    address = profile.gateway;
                    interface = "eth0";
                  };
                  inherit (profile) nameservers;
                  firewall.allowedTCPPorts = [ 22 ];
                };

                # The stock installer has empty local passwords and console
                # autologin. These headless bootstraps accept only the root
                # keys that survive into each installed host configuration.
                services.getty.autologinUser = lib.mkForce null;
                users.users = {
                  nixos.initialHashedPassword = lib.mkForce "!";
                  root = {
                    initialHashedPassword = lib.mkForce "!";
                    openssh.authorizedKeys.keys = profile.adminSshKeys;
                  };
                };
                services.openssh = {
                  enable = true;
                  settings = {
                    AllowUsers = [ "root" ];
                    KbdInteractiveAuthentication = false;
                    PasswordAuthentication = false;
                    PermitRootLogin = lib.mkForce "prohibit-password";
                    X11Forwarding = false;
                  };
                };

                # thornix-provision checks this over a host-key-pinned SSH
                # connection before it is allowed to invoke Disko.
                environment.etc."thornix-installer-profile".text = "${profile.installerProfile}\n";
              }
            )
          ];
        };

      installerIso =
        installer: "${installer.config.system.build.isoImage}/${installer.config.image.filePath}";
      profiles = lib.mapAttrs (
        _name: profile:
        profile
        // {
          bootstrapIso = installerIso (mkInstaller profile);
        }
      ) validatedProfiles;
      profileData = pkgs.writeText "thornix-provision-profiles.json" (builtins.toJSON profiles);

      # nixos-anywhere 1.13 defaults to /dev/null known_hosts and disabled
      # host-key checking. Remove only those two defaults; the provisioner
      # supplies a freshly captured, strict per-run known_hosts file after it
      # has confirmed that the selected profile's address was unused.
      strictNixosAnywhere = pkgs.nixos-anywhere.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/nixos-anywhere.sh \
            --replace-fail \
              'declare -a sshArgs=("-o" "IdentitiesOnly=yes" "-i" "$tempDir/nixos-anywhere" "-o" "UserKnownHostsFile=/dev/null" "-o" "StrictHostKeyChecking=no")' \
              'declare -a sshArgs=("-o" "IdentitiesOnly=yes" "-i" "$tempDir/nixos-anywhere")'
        '';
      });

      thornixProvision = pkgs.writeShellApplication {
        name = "thornix-provision";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
          pkgs.iproute2
          pkgs.iputils
          pkgs.jq
          pkgs.nix
          pkgs.openssh
          pkgs.sudo
          strictNixosAnywhere
        ];
        runtimeEnv.THORNIX_PROFILE_DATA = profileData;
        text = builtins.readFile ./proxmox-provisioner.sh;
      };
    in
    {
      environment.systemPackages = [ thornixProvision ];
      system.build.thornixProvisioner = thornixProvision;
    };
}
