{ ... }:
{
  # granite's media pool, exported from hosts/granite/nfs.nix and permitted for
  # this host's 192.168.1.6 address. The pool is owned by the *arr stack on
  # granite, so the workstation only ever reads from it.
  #
  # Access needs the `media` group, which `thorn-admin` pins to the server's
  # GID: `/platter/media` is `2770 root:media`, and NFSv4 with AUTH_SYS carries
  # numeric GIDs only.
  fileSystems."/mnt/media" = {
    device = "truenas.guildedthorn.arpa:/platter/media";
    fsType = "nfs";
    options = [
      #"ro"
      "vers=4.2"
      "proto=tcp"
      "nofail"
      # Media is only read while something is playing, so never block boot and
      # do not hold the mount open once the session is done with it.
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      # A player that opens a file while granite is rebooting should fail
      # quickly instead of hanging forever on a hard mount.
      "x-systemd.device-timeout=10s"
    ];
  };
}
