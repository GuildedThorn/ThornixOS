{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;

  # The bot's whole dotenv as one opaque secret. Values override the
  # defaults baked into Resources/config.json — TOKEN, Discord__OwnerId,
  # Discord__AuditChannelId, Lavalink__Authorization, RabbitMQ__UserName,
  # RabbitMQ__Password, Radio__*, Moderation__WarnStorePath, ...
  # Edit with `sops hosts/thornbot/secrets.yaml`.
  sops.secrets.thornbot_env.restartUnits = [ "thornbot.service" ];
}
