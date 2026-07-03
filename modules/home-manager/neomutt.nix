{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.neomutt;

      mailNotify = pkgs.writeShellApplication {
        name = "mail-notify";
        runtimeInputs = [
          pkgs.notmuch
          pkgs.libnotify
          pkgs.jq
        ];
        text = ''
          notmuch new

          while IFS=$'\t' read -r from subject; do
            notify-send -a "Mail" "New mail from $from" "$subject"
          done < <(notmuch search --format=json --output=summary tag:new | jq -r '.[] | [.authors, .subject] | @tsv')

          notmuch tag -new -- tag:new
        '';
      };
    in
    {
      options.thorn.programs.neomutt.enable =
        lib.mkEnableOption "Thorn's neomutt/mbsync/msmtp/notmuch email stack";

      config = lib.mkIf cfg.enable {
        programs.notmuch = {
          enable = true;
          new.tags = [
            "unread"
            "inbox"
            "new"
          ];
        };
        programs.msmtp.enable = true;
        programs.mbsync.enable = true;
        programs.neomutt.enable = true;

        services.mbsync = {
          enable = true;
          postExec = "${mailNotify}/bin/mail-notify";
        };
      };
    };
}
