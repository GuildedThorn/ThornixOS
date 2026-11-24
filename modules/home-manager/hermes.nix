{ inputs, ... }:
{
  homeManager.modules.thorn =
    { config, lib, ... }:
    {
      # Hermes keeps all of its state in ~/.hermes: sessions, memories,
      # skills, cron jobs and credentials. Installing the CLI through Home
      # Manager leaves that directory editable, so `hermes setup` and
      # `hermes model` keep working. The services module would take ownership
      # of the profile and block runtime config changes, so it stays off.
      imports = [ inputs.hermes.homeManagerModules.default ];

      options.thorn.programs.hermes = {
        enable = lib.mkEnableOption "the Hermes Agent CLI";
      };

      config = lib.mkIf config.thorn.programs.hermes.enable {
        programs.hermes-agent.enable = true;
      };
    };
}
