{ ... }:
{
  # Control channel for the FLARE detonation guest.
  #
  # The guest already runs the QEMU guest agent, but nothing in the
  # configuration could reach it: the Windows VM had no virtio-serial
  # device presented, and this host's `qm` wrapper rejects guest-exec
  # outright. This module ships a pvesh-backed wrapper so detonation
  # automation does not depend on the VNC console, on guest credentials the
  # repo does not hold, or on SMB.
  nixos.modules.services-flare-agent =
    { pkgs, ... }:
    let
      flareAgent = pkgs.writeShellApplication {
        name = "flare-agent";
        runtimeInputs = [
          # tr, dd, base64, sha256sum, cut, wc, sleep, basename
          pkgs.coreutils
          # awk, for parsing `qm status`
          pkgs.gawk
          # iconv, for the UTF-16LE encoding PowerShell's -EncodedCommand needs
          pkgs.glibc
          # hostname, as a fallback when /proc is not readable
          pkgs.inetutils
          # JSON handling for every agent response
          pkgs.jq
          # YARA pattern matching
          pkgs.yara
          # capa capability analysis
          pkgs.capa
          # tcpdump for PCAP capture
          pkgs.tcpdump
        ];
        text = builtins.readFile ./flare-agent.sh;
        excludeShellChecks = [
          # Single-quoted trap bodies and PowerShell heredocs: shellcheck cannot
          # see the assignments, and the $ are meant to reach PowerShell.
          "SC2154"
          "SC2016"
        ];
      };
    in
    {
      environment.systemPackages = [ flareAgent ];

      # Exposed so CI can build and smoke-test the wrapper without
      # activating the whole desktop closure.
      system.build.flareAgent = flareAgent;
    };
}
