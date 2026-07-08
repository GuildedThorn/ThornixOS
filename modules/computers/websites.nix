{
  config,
  inputs,
  ...
}:
{
  flake.nixosConfigurations.websites = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-clamav
      config.nixos.modules.services-ssh

      inputs.guildedthorn-com.nixosModules.default

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/websites/hardware-configuration.nix"
      "${inputs.self}/hosts/websites/disko.nix"
      "${inputs.self}/hosts/websites/networking.nix"
      "${inputs.self}/hosts/websites/secrets.nix"

      (
        { config, lib, pkgs, ... }:
        {
          boot = {
            growPartition = true;
            # BIOS boot via GRUB on the whole disk. disko already registers
            # /dev/sda as a GRUB device; force a single entry so the two
            # definitions don't merge into a duplicate (mirroredBoots assert).
            loader.grub = {
              enable = true;
              devices = lib.mkForce [ "/dev/sda" ];
              efiSupport = false;
            };
            # Keep predictable names disabled so the NIC stays "eth0",
            # matching the static config in hosts/websites/networking.nix.
            kernelParams = [ "net.ifnames=0" ];
          };

          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "prohibit-password";
            settings.PasswordAuthentication = false;
          };
          services.qemuGuest.enable = true;

          services.guildedthorn = {
            enable = true;
            port = 8080;
            environmentFile = config.sops.secrets.guildedthorn_env.path;
          };

          services.owncast = {
            enable = true;
            listen = "127.0.0.1";
            port = 8090;
            rtmp-port = 1935;
          };

          services.rabbitmq.enable = true;
          # epmd listens on IPv6 by default, which is disabled on this host;
          # RabbitMQ only needs it on loopback.
          services.epmd.listenStream = "127.0.0.1:4369";

          systemd.services.cloudflared = {
            description = "Cloudflare Tunnel";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate --loglevel info run";
              EnvironmentFile = config.sops.templates."cloudflared.env".path;
              Restart = "on-failure";
              RestartSec = 5;
              DynamicUser = true;
            };
          };

        }
      )
    ];
  };
}
