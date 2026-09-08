{ inputs, lib, ... }:
{
  # NixOS module for ThornBot (the Discord bot) — consumes the upstream
  # guildedthorn-bot flake's nixosModule and layers on the fleet conventions:
  # sops-managed environment, a local loopback-only RabbitMQ (for
  # GuestBookService), and systemd ordering so the bot only starts after its
  # messaging broker and its dedicated RabbitMQ user exist.
  nixos.modules.services-thornbot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.thornbot or { };
    in
    {
      imports = [ inputs.guildedthorn-bot.nixosModules.default ];

      config = lib.mkIf (cfg.enable or false) {
        # The bot's whole dotenv is one opaque sops secret
        # (TOKEN, Discord__OwnerId, Discord__AuditChannelId, Lavalink__Authorization,
        # RabbitMQ__UserName/__Password, Radio__*, ...), materialized by
        # hosts/thornbot/secrets.nix. Values override Resources/config.json.
        services.thornbot.environmentFile = lib.mkForce config.sops.secrets.thornbot_env.path;

        # Guestbook messages come in over RabbitMQ. Run it locally and
        # loopback-only so no AMQP port is ever exposed to the LAN.
        services.rabbitmq = {
          enable = true;
          listenAddress = "127.0.0.1";
          port = 5672;
          configItems = {
            # Keep AMQP and the management API on loopback — the firewall
            # never opens these ports, so nothing ever leaves 127.0.0.1.
            # Note: do NOT also set "listeners.tcp.default" here. The nixpkgs
            # module already injects "listeners.tcp.1" from listenAddress/port
            # (lib.mkDefault); adding a second entry for the same socket makes
            # RabbitMQ die at boot with {could_not_start_listener,{already_started,...}}.
            "management.tcp.port" = "-1";
          };
        };

        # epmd listens on IPv6 by default, which is disabled on this host
        # (enableIPv6 = false). Like the websites host, it must cover 127.0.0.2
        # too: RabbitMQ's node is rabbit@thornbot and NixOS maps the bare
        # hostname to 127.0.0.2, so epmd pinned to 127.0.0.1 alone leaves rabbit
        # unable to register. 4369 stays LAN-invisible (not in allowedTCPPorts).
        services.epmd.listenStream = "0.0.0.0:4369";

        # Create the RabbitMQ user the bot authenticates as, using the same
        # credentials from the sops env file the bot will read. Idempotent;
        # runs once before thornbot.service starts and after rabbitmq is up.
        systemd.services.thornbot-rabbitmq-user = {
          description = "Provision the ThornBot RabbitMQ user";
          wantedBy = [ "multi-user.target" ];
          after = [ "rabbitmq.service" ];
          wants = [ "rabbitmq.service" ];
          before = [ "thornbot.service" ];
          requiredBy = [ "thornbot.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -euo pipefail
            env_file=${config.sops.secrets.thornbot_env.path}
            user=$(sed -n 's/^RabbitMQ__UserName=//p' "$env_file")
            pass=$(sed -n 's/^RabbitMQ__Password=//p' "$env_file")
            if [ -z "$user" ] || [ -z "$pass" ]; then
              echo "error: RabbitMQ__UserName/RabbitMQ__Password missing from ${"$"}env_file" >&2
              exit 1
            fi
            rabbitmqctl add_user "$user" "$pass" || true
            rabbitmqctl set_permissions -p / "$user" '.*' '.*' '.*' || true
            echo "ThornBot RabbitMQ user '$user' provisioned."
          '';
        };

        # Ensure the bot waits for its broker + user and restarts if the
        # provisioning oneshot is ever re-run after a credential change.
        systemd.services.thornbot = {
          after = [
            "thornbot-rabbitmq-user.service"
            "rabbitmq.service"
          ];
          wants = [ "thornbot-rabbitmq-user.service" ];
        };

        # Headless service VM: hardening handled by profile-qemu-server +
        # the bot's own unit hardening. SSH is key-only.
        services.openssh = lib.mkIf (config.services.openssh.enable or false) {
          openFirewall = false;
        };
      };
    };
}
