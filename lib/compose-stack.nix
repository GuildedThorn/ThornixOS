{ lib, pkgs }:
{
  name,
  project,
  file,
  lockFile,
  adminCommandName,
  environmentFile ? null,
  checkEnvironmentFile ? null,
  startWait ? 1800,
  stopTimeout ? 60,
}:
assert lib.assertMsg (
  environmentFile == null || checkEnvironmentFile != null
) "${name}: Compose validation needs a non-secret fixture environment";
let
  commandFor =
    environment:
    lib.escapeShellArgs (
      [ "${pkgs.docker-compose}/bin/docker-compose" ]
      ++ lib.optionals (environment != null) [
        "--env-file"
        environment
      ]
      ++ [
        "--project-name"
        project
        "--file"
        file
      ]
    );
  command = commandFor environmentFile;
in
{
  inherit command;

  start = pkgs.writeShellScript "${name}-start" ''
    set -o errexit -o nounset -o pipefail
    exec 9>${lib.escapeShellArg lockFile}
    ${pkgs.util-linux}/bin/flock --wait ${toString startWait} 9
    exec ${command} up --detach --remove-orphans
  '';

  # Failure to acquire the shutdown lock remains non-fatal. A feed update or
  # administrator action may hold it; stopping must not destroy stack state.
  stop = pkgs.writeShellScript "${name}-stop" ''
    set -o nounset -o pipefail
    exec 9>${lib.escapeShellArg lockFile}
    ${pkgs.util-linux}/bin/flock --wait 60 9 || exit 0
    exec ${command} stop --timeout ${toString stopTimeout}
  '';

  check = pkgs.runCommand "${name}-compose-check" { nativeBuildInputs = [ pkgs.docker-compose ]; } ''
    export HOME="$TMPDIR"
    ${commandFor checkEnvironmentFile} config --quiet
    touch "$out"
  '';

  adminCommand = pkgs.writeShellApplication {
    name = adminCommandName;
    runtimeInputs = [ pkgs.docker-compose ];
    text = ''
      if ((EUID != 0)); then
        echo ${lib.escapeShellArg "error: ${adminCommandName} must run as root"} >&2
        exit 1
      fi
      exec ${command} "$@"
    '';
  };
}
