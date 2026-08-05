{ inputs, ... }:
{
  nixos.modules.services-proxmox-provisioner =
    { lib, pkgs, ... }:
    let
      adminSshKeys = import ../../hosts/identity/admin-ssh-keys.nix;

      identityInstaller = inputs.nixpkgs.lib.nixosSystem {
        system = pkgs.stdenv.hostPlatform.system;
        modules = [
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          (
            { lib, ... }:
            {
              isoImage.volumeID = "THORNIX_IDENTITY";

              # The VM's only NIC is virtio. A stable interface name lets the
              # installer come up at identity's final address without DHCP or
              # a cloud-init dependency.
              boot.kernelParams = [ "net.ifnames=0" ];
              networking = {
                hostName = "thornix-identity-installer";
                enableIPv6 = false;
                useDHCP = lib.mkForce false;
                networkmanager.enable = lib.mkForce false;
                interfaces.eth0 = {
                  useDHCP = false;
                  ipv4.addresses = [
                    {
                      address = "172.16.25.52";
                      prefixLength = 24;
                    }
                  ];
                };
                defaultGateway = {
                  address = "172.16.25.1";
                  interface = "eth0";
                };
                nameservers = [
                  "172.16.25.1"
                  "1.1.1.1"
                ];
                firewall.allowedTCPPorts = [ 22 ];
              };

              # The stock installer has empty local passwords and console
              # autologin. This headless bootstrap accepts only the same root
              # keys that survive into the installed identity configuration.
              services.getty.autologinUser = lib.mkForce null;
              users.users = {
                nixos.initialHashedPassword = lib.mkForce "!";
                root = {
                  initialHashedPassword = lib.mkForce "!";
                  openssh.authorizedKeys.keys = adminSshKeys;
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
              environment.etc."thornix-installer-profile".text = "identity/v1\n";
            }
          )
        ];
      };

      identityInstallerIso = "${identityInstaller.config.system.build.isoImage}/${identityInstaller.config.image.filePath}";

      # nixos-anywhere 1.13 defaults to /dev/null known_hosts and disabled
      # host-key checking. Remove only those two defaults; the provisioner
      # supplies a freshly captured, strict per-run known_hosts file after it
      # has confirmed that identity's address was unused.
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
          pkgs.nix
          pkgs.openssh
          pkgs.sudo
          strictNixosAnywhere
        ];
        runtimeEnv = {
          THORNIX_ADMIN_SSH_KEYS = lib.concatStringsSep "\n" adminSshKeys;
          THORNIX_BOOTSTRAP_ISO = identityInstallerIso;
          THORNIX_CA_CERTIFICATE = "${inputs.self}/certs/ThornCloud_CA.crt";
          THORNIX_DEFAULT_FLAKE = "github:GuildedThorn/ThornixOS/deploy-identity#identity";
        };
        text = builtins.readFile ./proxmox-provisioner.sh;
      };
    in
    {
      environment.systemPackages = [ thornixProvision ];
    };
}
