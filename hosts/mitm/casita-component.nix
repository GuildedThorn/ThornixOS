let
  deckHost = "172.16.25.26";
  workflowModelHost = "192.168.1.6";
  workflowModelName = "qwen3:14b";
  workflowModelUrl = "http://${workflowModelHost}:11435";
in
(
  {
    lib,
    pkgs,
    ...
  }:
  let
    casitaAssist = pkgs.buildHomeAssistantComponent {
      owner = "GuildedThorn";
      domain = "casita_assist";
      version = "1.1.7";
      src = ../../packages/casita-assist;
    };
    storageSource = pkgs.writeText "casita-ha-storage.py" (
      builtins.readFile ../../packages/casita-ha-storage.py
    );
    storageTestSource = pkgs.writeText "casita-ha-storage_test.py" (
      builtins.readFile ../../packages/casita-ha-storage_test.py
    );
    routingSource = pkgs.writeText "routing.py" (
      builtins.readFile ../../packages/casita-assist/routing.py
    );
    routingTestSource = pkgs.writeText "routing_test.py" (
      builtins.readFile ../../packages/casita-assist/routing_test.py
    );
    storageTests =
      pkgs.runCommand "casita-ha-storage-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
        ''
            mkdir test
            cp ${storageSource} test/casita-ha-storage.py
            cp ${storageTestSource} test/casita-ha-storage_test.py
            cd test
            python3 -B casita-ha-storage_test.py
          touch "$out"
        '';
    routingTests = pkgs.runCommand "casita-routing-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      mkdir test
      cp ${routingSource} test/routing.py
      cp ${routingTestSource} test/routing_test.py
      cd test
      python3 -B routing_test.py
      touch "$out"
    '';
    storageMigration = pkgs.writeShellApplication {
      name = "casita-ha-storage";
      text = ''
        exec ${pkgs.python3}/bin/python3 ${storageSource} \
          --config-dir /var/lib/hass \
          --deck-host ${deckHost} \
          --model granite4.1:3b \
          --workflow-url ${workflowModelUrl} \
          --workflow-model ${workflowModelName} \
          --workflow-keep-alive 300 \
          --workflow-num-ctx 8192
      '';
    };
  in
  {
    system.checks = [
      storageTests
      routingTests
    ];
    services.home-assistant = {
      customComponents = [ casitaAssist ];
      config.casita_assist = { };
    };
    systemd.services.home-assistant.preStart = lib.mkAfter ''
      ${storageMigration}/bin/casita-ha-storage
    '';

    thorn.backup = {
      enable = true;
      schedule = "*-*-* 04:40:00";
      paths = [ "/var/lib/hass" ];
      exclude = [
        "/var/lib/hass/.cache"
        "/var/lib/hass/deps"
        "/var/lib/hass/home-assistant.log*"
        "/var/lib/hass/tts"
      ];
      quiesceServices = [ "home-assistant.service" ];
      restorePaths = [
        "/var/lib/hass/.storage/core.config_entries"
        "/var/lib/hass/home-assistant_v2.db"
      ];
      restoreValidationCommand = ''
        ${pkgs.sqlite}/bin/sqlite3 \
          "$RESTORE_ROOT/var/lib/hass/home-assistant_v2.db" \
          'PRAGMA integrity_check;' \
          | ${pkgs.gnugrep}/bin/grep --fixed-strings --line-regexp ok >/dev/null
      '';
    };
  }
)
