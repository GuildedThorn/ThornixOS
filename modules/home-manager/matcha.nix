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

      matcha = pkgs.matcha.overrideAttrs (oldAttrs: {
        # Matcha leaks failed-auth sockets, deletes Gmail labels instead of
        # moving mail to Trash, and runs rapid email actions concurrently.
        patches = (oldAttrs.patches or [ ]) ++ [
          (pkgs.writeText "matcha-imap-reliability.patch" ''
            diff --git a/fetcher/fetcher.go b/fetcher/fetcher.go
            --- a/fetcher/fetcher.go
            +++ b/fetcher/fetcher.go
            @@ -443,9 +443,11 @@
             ''\tif account.IsOAuth2() {
             ''\t''\ttoken, err := config.GetOAuth2Token(account.Email)
             ''\t''\tif err != nil {
            +''\t''\t''\tc.Close() //nolint:errcheck,gosec
             ''\t''\t''\treturn nil, fmt.Errorf("oauth2: %w", err)
             ''\t''\t}
             ''\t''\tif err := c.Authenticate(newXOAuth2Client(account.Email, token)); err != nil {
            +''\t''\t''\tc.Close() //nolint:errcheck,gosec
             ''\t''\t''\treturn nil, fmt.Errorf("XOAUTH2 authentication failed: %w", err)
             ''\t''\t}
             ''\t} else {
            @@ -455,6 +457,7 @@
             ''\t''\t''\treturn nil, fmt.Errorf("no password available for %s: keyring or pass_cmd returned nothing (see https://docs.matcha.email/Features/PassCmd)", account.Email)
             ''\t''\t}
             ''\t''\tif err := c.Login(account.Email, password).Wait(); err != nil {
            +''\t''\t''\tc.Close() //nolint:errcheck,gosec
             ''\t''\t''\treturn nil, fmt.Errorf("authentication error: %w", err)
             ''\t''\t}
             ''\t}
            @@ -1458,6 +1461,18 @@
             ''\t}
             
             ''\tuidSet := imap.UIDSetNum(imap.UID(uid))
            +''\t// Gmail deletion must move mail to Trash. Marking it deleted and
            +''\t// expunging only removes the current Gmail label.
            +''\tif account.ServiceProvider == config.ProviderGmail {
            +''\t''\ttrashMailbox, trashErr := getMailboxByAttr(c, imap.MailboxAttrTrash)
            +''\t''\tif trashErr != nil {
            +''\t''\t''\ttrashMailbox = getTrashMailbox(account)
            +''\t''\t}
            +''\t''\tif mailbox != trashMailbox {
            +''\t''\t''\t_, moveErr := c.Move(uidSet, trashMailbox).Wait()
            +''\t''\t''\treturn moveErr
            +''\t''\t}
            +''\t}
             ''\tif err := c.Store(uidSet, &imap.StoreFlags{
             ''\t''\tOp:     imap.StoreFlagsAdd,
             ''\t''\tSilent: true,
            @@ -1535,6 +1550,18 @@
             ''\t}
             
             ''\tuidSet := uidsToUIDSet(uids)
            +''\t// Gmail deletion must move mail to Trash. Marking it deleted and
            +''\t// expunging only removes the current Gmail label.
            +''\tif account.ServiceProvider == config.ProviderGmail {
            +''\t''\ttrashMailbox, trashErr := getMailboxByAttr(c, imap.MailboxAttrTrash)
            +''\t''\tif trashErr != nil {
            +''\t''\t''\ttrashMailbox = getTrashMailbox(account)
            +''\t''\t}
            +''\t''\tif mailbox != trashMailbox {
            +''\t''\t''\t_, moveErr := c.Move(uidSet, trashMailbox).Wait()
            +''\t''\t''\treturn moveErr
            +''\t''\t}
            +''\t}
             ''\tif err := c.Store(uidSet, &imap.StoreFlags{
             ''\t''\tOp:     imap.StoreFlagsAdd,
             ''\t''\tSilent: true,
            diff --git a/daemon/daemon.go b/daemon/daemon.go
            --- a/daemon/daemon.go
            +++ b/daemon/daemon.go
            @@ -37,6 +37,7 @@
             
             ''\t// Mutex for disk cache updates.
             ''\tcacheMu sync.Mutex
            +''\temailActionMu sync.Mutex
             
             ''\t// IMAP IDLE watcher for push notifications.
             ''\tidleWatcher *fetcher.IdleWatcher
            diff --git a/daemon/handler.go b/daemon/handler.go
            --- a/daemon/handler.go
            +++ b/daemon/handler.go
            @@ -145,6 +145,9 @@
             }
             
             func (d *Daemon) handleDeleteEmails(ctx context.Context, _ *daemonrpc.Conn, params json.RawMessage) (any, error) {
            +''\td.emailActionMu.Lock()
            +''\tdefer d.emailActionMu.Unlock()
            +
             ''\targs, err := decodeParams[daemonrpc.DeleteEmailsParams](params)
             ''\tif err != nil {
             ''\t''\treturn nil, parseError(err)
            @@ -165,6 +168,9 @@
             }
             
             func (d *Daemon) handleArchiveEmails(ctx context.Context, _ *daemonrpc.Conn, params json.RawMessage) (any, error) {
            +''\td.emailActionMu.Lock()
            +''\tdefer d.emailActionMu.Unlock()
            +
             ''\targs, err := decodeParams[daemonrpc.ArchiveEmailsParams](params)
             ''\tif err != nil {
             ''\t''\treturn nil, parseError(err)
            @@ -185,6 +191,9 @@
             }
             
             func (d *Daemon) handleMoveEmails(ctx context.Context, _ *daemonrpc.Conn, params json.RawMessage) (any, error) {
            +''\td.emailActionMu.Lock()
            +''\tdefer d.emailActionMu.Unlock()
            +
             ''\targs, err := decodeParams[daemonrpc.MoveEmailsParams](params)
             ''\tif err != nil {
             ''\t''\treturn nil, parseError(err)
          '')
        ];
      });

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
        home.packages = [ matcha ];

        xdg.configFile."matcha/config.json".text = builtins.toJSON {
          accounts = lib.mapAttrsToList mkAccount cfg.accounts;
        };
      };
    };
}
