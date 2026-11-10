{ pkgs, lib }:
let
  compose = pkgs.writeShellScriptBin "docker-compose" ''
    printf '%s\0' "$@" >> "$COMPOSE_TEST_LOG"
  '';
  fixture = pkgs.writeText "compose-test.yaml" "services: {}\n";
  stack =
    import ../lib/compose-stack.nix
      {
        inherit lib;
        pkgs = pkgs // {
          docker-compose = compose;
        };
      }
      {
        name = "compose-lifecycle-test";
        project = "project with spaces";
        file = fixture;
        lockFile = "/tmp/thornix-compose-test.lock";
        adminCommandName = "compose-test-admin";
        startWait = 0;
        stopTimeout = 90;
      };
in
pkgs.runCommand "thornix-compose-lifecycle-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    START_SCRIPT = stack.start;
    STOP_SCRIPT = stack.stop;
    ADMIN_SCRIPT = lib.getExe stack.adminCommand;
    COMPOSE_FILE = fixture;
  }
  ''
    python3 ${./compose_stack_test.py}
    touch "$out"
  ''
