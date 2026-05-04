# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  pkgs,
  username,
  ...
}:
{

  imports = [
    # Include the results of the hardware scan.
    #./hardware-configuration.nix
    ./users/${username}/${username}.nix
  ];

  users.users.${username} = {
    isNormalUser = true;
  };

  # -------------------------
  # Bootloader (UEFI systems)
  # -------------------------
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;

  # If you're on legacy BIOS instead, use this instead:
  # boot.loader.grub.enable = true;
  # boot.loader.grub.device = "/dev/sda";

  # -------------------------
  # Experimental Features
  # -------------------------
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # -------------------------
  # DNS Resolver
  # -------------------------
  services.resolved.enable = false;

  # -------------------------
  # Nix Helper
  # -------------------------
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/etc/nixos"; # sets NH_OS_FLAKE variable for you
  };

  # List packages installed in system profile. To search, run:
  # $ nix search <package>
  environment.systemPackages = with pkgs; [
    git
    gnumake

    bmon
    iftop
    iperf3

    nixfmt
    nixfmt-tree
  ];

  # Allow unfree packages

  nixpkgs.config.allowUnfree = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
