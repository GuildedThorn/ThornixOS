{ pkgs, ... }:
let
  voiceVisualPage = pkgs.writeText "deck-voice-visual.html" (builtins.readFile ./voice-visual.html);
  voiceVisualSource = pkgs.writeText "deck-voice-visual.py" (builtins.readFile ./voice-visual.py);
  voiceVisualPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.websocket-client ]);
  voiceVisual = pkgs.writeShellApplication {
    name = "deck-voice-visual";
    runtimeInputs = [
      pkgs.alsa-utils
      pkgs.chromium
      pkgs.kdePackages.libkscreen
      pkgs.systemd
      pkgs.wireplumber
    ];
    text = ''
      exec ${voiceVisualPython}/bin/python3 ${voiceVisualSource} \
        --page ${voiceVisualPage} "$@"
    '';
  };
in
{
  home = {
    packages = [
      voiceVisual
      pkgs.kdePackages.plasma-bigscreen
      # Plasma Bigscreen imports org.kde.kdeconnect in its homescreen.
      pkgs.kdePackages.kdeconnect-kde
    ];
    stateVersion = "26.11";
  };

  systemd.user.services = {
    deck-voice-visual = {
      Unit = {
        Description = "Deck Voice visual assistant state server";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${voiceVisual}/bin/deck-voice-visual serve";
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };

    deck-voice-visual-kiosk = {
      Unit = {
        Description = "Deck Voice visual assistant on the external display";
        After = [
          "deck-voice-visual.service"
          "graphical-session.target"
        ];
        PartOf = [ "graphical-session.target" ];
        Requires = [ "deck-voice-visual.service" ];
      };
      Service = {
        ExecStart = "${voiceVisual}/bin/deck-voice-visual launch";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  xdg.dataFile."applications/deck-voice-visual.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Deck Voice Visual
    Comment=Open the TV visual assistant
    Exec=${pkgs.systemd}/bin/systemctl --user restart deck-voice-visual-kiosk.service
    Icon=audio-input-microphone
    Terminal=false
    Categories=Utility;AudioVideo;
    StartupNotify=false
  '';

  # SteamOS-style couch interface toggle. Plasma Bigscreen provides the
  # swap-session helper, which replaces only the Plasma shell and preserves
  # the normal desktop environment for the next toggle.
  xdg.dataFile."applications/deck-tv-mode.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Toggle TV Mode
    Comment=Switch between normal KDE and Plasma Bigscreen
    Exec=plasma-bigscreen-swap-session
    Icon=video-display
    Terminal=false
    Categories=Settings;AudioVideo;
    StartupNotify=true
  '';
}
