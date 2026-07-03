{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.matcha;

      mkAccount =
        id: a:
        {
          inherit id;
          name = a.name;
          email = a.email;
          service_provider = a.serviceProvider;
          # Matcha shells this out at startup and uses stdout as the
          # password - same trick as weechat's sslCert: the secret path
          # is resolved by the caller (osConfig.sops.secrets.*.path) and
          # never touches the nix store or config.json itself.
          pass_cmd = "cat ${a.secretPath}";
        }
        // lib.optionalAttrs (a.sendAsEmail != null) { send_as_email = a.sendAsEmail; }
        // lib.optionalAttrs (a.imapServer != null) { imap_server = a.imapServer; }
        // lib.optionalAttrs (a.imapPort != null) { imap_port = a.imapPort; }
        // lib.optionalAttrs (a.smtpServer != null) { smtp_server = a.smtpServer; }
        // lib.optionalAttrs (a.smtpPort != null) { smtp_port = a.smtpPort; }
        // lib.optionalAttrs a.insecure { insecure = true; };
    in
    {
      options.thorn.programs.matcha = {
        enable = lib.mkEnableOption "Thorn's matcha terminal email client configuration";

        realName = lib.mkOption {
          type = lib.types.str;
          default = "Jamie Duddleston";
          description = "Default display name used on every configured account.";
        };

        accounts = lib.mkOption {
          default = { };
          description = "Email accounts to declare in matcha's config.json, keyed by account id.";
          type = lib.types.attrsOf (
            lib.types.submodule (
              { config, ... }:
              {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    default = cfg.realName;
                    description = "Display name used for outgoing mail on this account.";
                  };
                  email = lib.mkOption {
                    type = lib.types.str;
                    example = "jane@gmail.com";
                    description = "Login/fetch address for this account.";
                  };
                  secretPath = lib.mkOption {
                    type = lib.types.path;
                    description = "Path to a file containing the account password/app-password, read via pass_cmd.";
                  };
                  serviceProvider = lib.mkOption {
                    type = lib.types.enum [
                      "gmail"
                      "outlook"
                      "icloud"
                      "custom"
                    ];
                    default = "gmail";
                    description = "Matcha provider preset - fills in IMAP/SMTP servers for gmail/outlook/icloud.";
                  };
                  sendAsEmail = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Outgoing From address, if different from the login address.";
                  };
                  imapServer = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "IMAP host, required when serviceProvider = \"custom\".";
                  };
                  imapPort = lib.mkOption {
                    type = lib.types.nullOr lib.types.port;
                    default = null;
                  };
                  smtpServer = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "SMTP host, required when serviceProvider = \"custom\".";
                  };
                  smtpPort = lib.mkOption {
                    type = lib.types.nullOr lib.types.port;
                    default = null;
                  };
                  insecure = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                  };
                };
              }
            )
          );
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.matcha ];

        xdg.configFile."matcha/config.json".text = builtins.toJSON {
          accounts = lib.mapAttrsToList mkAccount cfg.accounts;
        };
      };
    };
}
