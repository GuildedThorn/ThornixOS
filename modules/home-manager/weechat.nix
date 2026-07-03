{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.weechat;

      mkServerLines =
        name: s:
        lib.concatStringsSep "\n" (
          [
            "${name}.addresses = \"${s.address}\""
            "${name}.ssl = on"
            "${name}.ssl_verify = on"
            "${name}.autoconnect = ${if s.autoconnect then "on" else "off"}"
            "${name}.nicks = \"${cfg.nick}\""
            "${name}.username = \"${cfg.nick}\""
            "${name}.realname = \"${cfg.nick}\""
            # Give CertFP/SASL registration time to land before autojoin
            # fires, otherwise the first autojoin channel can race ahead
            # of auth (join gets sent while still unregistered, and
            # silently fails until the channel is joined manually).
            "${name}.command_delay = \"${toString s.commandDelay}\""
          ]
          # CertFP: a client cert (PEM, cert+key concatenated) presented
          # during the TLS handshake. Its fingerprint still has to be
          # registered once with NickServ (`/msg NickServ CERT ADD`) before
          # this identifies you. `sasl` additionally requests IRCv3 SASL
          # EXTERNAL on top of that - only enable it for networks that
          # actually advertise the `sasl` capability (OFTC's ircd doesn't;
          # it auto-identifies from the cert at registration instead, and
          # requesting an unsupported cap just loops connect/disconnect).
          ++ lib.optionals (s.sslCert != null) [
            "${name}.ssl_cert = \"${s.sslCert}\""
          ]
          ++ lib.optionals (s.sslCert != null && s.sasl) [
            "${name}.sasl_mechanism = \"external\""
          ]
          ++ lib.optionals (s.autojoin != [ ]) [
            "${name}.autojoin = \"${lib.concatStringsSep "," s.autojoin}\""
          ]
        );
    in
    {
      options.thorn.programs.weechat = {
        enable = lib.mkEnableOption "Thorn's WeeChat IRC client configuration";

        nick = lib.mkOption {
          type = lib.types.str;
          default = "GuildedThorn";
          description = "Default nick/username/realname used on every configured server.";
        };

        servers = lib.mkOption {
          default = { };
          description = "IRC servers to declare in irc.conf, keyed by server name.";
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                address = lib.mkOption {
                  type = lib.types.str;
                  example = "irc.oftc.net/6697";
                  description = "host/port passed to irc.server.<name>.addresses.";
                };
                sslCert = lib.mkOption {
                  type = lib.types.nullOr lib.types.path;
                  default = null;
                  description = "Path to a PEM file (cert+key) for CertFP auth.";
                };
                sasl = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Also request SASL EXTERNAL on top of the CertFP cert. Requires the network to advertise the `sasl` capability.";
                };
                autojoin = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Channels to autojoin on connect, e.g. [ \"#oftc\" ].";
                };
                autoconnect = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                commandDelay = lib.mkOption {
                  type = lib.types.ints.unsigned;
                  default = 3;
                  description = "Seconds to wait after connecting before autojoining channels, to let CertFP/SASL registration finish first.";
                };
              };
            }
          );
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.weechat ];

        xdg.configFile."weechat/irc.conf".text = ''
          [server]
          ${lib.concatStringsSep "\n\n" (lib.mapAttrsToList mkServerLines cfg.servers)}
        '';
      };
    };
}
