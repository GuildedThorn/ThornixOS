{
  vmid = 120;
  address = "172.16.25.68";
  isoLabel = "THORNIX_THORNBOT";
  diskSerial = "THORNIX_THORNBOT_120";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 4096;
    # .NET + Lavalink + RabbitMQ working set is well under 2 GiB after start,
    # but music/radio buffering can spike; balloon down to a 2 GiB floor.
    minimumMemoryMiB = 2048;
    # A current NixOS closure plus one rollback generation needs headroom.
    diskGiB = 40;
  };

  readiness = {
    displayName = "ThornBot";
    label = "ThornBot Discord bot with Lavalink, moderation, and guestbook";
    timeoutSeconds = 1200;
    units = [
      "rabbitmq.service"
      "thornbot.service"
    ];
    # ThornBot is an outbound Discord client with no web UI and no public
    # TLS, so there is intentionally no httpCheck/tftpCheck to probe.
    readyLines = [
      "ThornBot connects outbound to Discord; there is no web admin interface."
      "Add a pfSense host override for thornbot.guildedthorn.arpa -> 172.16.25.68."
      "Secrets live in sops hosts/thornbot/secrets.yaml (TOKEN, Lavalink/RabbitMQ credentials)."
      "GuestBookService consumes guestbook_messages off the local 127.0.0.1 RabbitMQ."
    ];
  };
}
