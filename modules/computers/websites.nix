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

      config.nixos.modules.services-canary
      config.nixos.modules.services-clamav
      config.nixos.modules.services-crowdsec
      config.nixos.modules.services-ssh
      config.nixos.modules.services-suricata

      inputs.guildedthorn-com.nixosModules.default

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/websites/hardware-configuration.nix"
      "${inputs.self}/hosts/websites/disko.nix"
      "${inputs.self}/hosts/websites/networking.nix"
      "${inputs.self}/hosts/websites/secrets.nix"

      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          # Headless and internet-facing: nobody logs in interactively, so
          # the default "sessions" exec scope would record nothing here —
          # leaving the host most likely to be reached through a service
          # exploit as the one with no execution telemetry at all. See
          # services-audit for the volume trade.
          thorn.audit.execScope = "all";

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

          # Complete boot.growPartition by growing the ext4 filesystem to
          # fill the enlarged partition on boot.
          fileSystems."/".autoResize = true;

          services.openssh = {
            enable = true;
            settings.PermitRootLogin = "prohibit-password";
            settings.PasswordAuthentication = false;
          };
          # Workstation key — without at least one authorized key this
          # headless host has no login path at all (no console passwords,
          # password auth off).
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+iFLtqnhkscz2qLK45nJVmGZIbQvIeIuW8tenAjX2p thorn@workstation"
          ];
          services.qemuGuest.enable = true;

          services.guildedthorn = {
            enable = true;
            port = 8080;
            environmentFile = config.sops.secrets.guildedthorn_env.path;
          };

          # The managed .NET heap can otherwise grow for days until this
          # small public VM starts swapping, even though the normal working
          # set after a restart is well below 256 MiB. Ask the kernel to
          # reclaim at 3 GiB and bound a genuine leak at 3.5 GiB; the
          # upstream unit already restarts on failure, so an exhausted cgroup
          # recovers without taking the rest of the host with it.
          systemd.services.guildedthorn.serviceConfig = {
            MemoryHigh = "3G";
            MemoryMax = "3500M";
            MemorySwapMax = "512M";
          };

          # Public traffic arrives through the Cloudflare tunnel, so on
          # eth0 it's just TLS to Cloudflare — the readable HTTP is on
          # loopback between cloudflared and the app. Watch both.
          thorn.suricata.interfaces = [
            "lo"
            "eth0"
          ];

          # A web host is attacked over IP; the switch's L2 chatter (STP
          # BPDUs every 2s reaching the VM bridge) is not this sensor's
          # problem and was 99% of its alert volume.
          thorn.suricata.bpfFilter = "ip or ip6 or arp";

          services.owncast = {
            enable = true;
            # cloudflared still reaches this locally; the firewall admits
            # direct HTTP only from the SOC for independent health probing.
            listen = "0.0.0.0";
            port = 8090;
            rtmp-port = 1935;
          };

          thorn.backup = {
            enable = true;
            schedule = "*-*-* 04:50:00";
            paths = [ "/var/lib/owncast" ];
            quiesceServices = [ "owncast.service" ];
            restorePaths = [ "/var/lib/owncast/data/owncast.db" ];
            restoreValidationCommand = ''
              ${pkgs.sqlite}/bin/sqlite3 \
                "$RESTORE_ROOT/var/lib/owncast/data/owncast.db" \
                'PRAGMA integrity_check;' \
                | ${pkgs.gnugrep}/bin/grep --fixed-strings --line-regexp ok >/dev/null
            '';
          };

          services.rabbitmq.enable = true;
          # epmd listens on IPv6 by default, which is disabled on this host.
          # It must cover 127.0.0.2 too: RabbitMQ's node is rabbit@websites,
          # and NixOS maps the bare hostname to 127.0.0.2, so epmd pinned to
          # 127.0.0.1 alone leaves rabbit unable to register (epmd_error
          # address crash loop). 4369 stays LAN-invisible — it's not in
          # firewall.allowedTCPPorts.
          services.epmd.listenStream = "0.0.0.0:4369";

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
