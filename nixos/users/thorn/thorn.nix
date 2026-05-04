{
  pkgs,
  lib,
  host,
  ...
}:

{

  imports = lib.optionals (builtins.pathExists ./hosts/${host}/configuration.nix) [
    ./hosts/${host}/configuration.nix
  ];

  home-manager.users.thorn = import ./home.nix;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  security.pki.certificates = [
    (builtins.readFile ./certs/ThornCloud_CA.crt)
  ];

  security.pam.services.login.enableGnomeKeyring = true;

  environment.systemPackages = with pkgs; [
    opensc
    zoxide
    swayosd

    wget
    gvfs
    samba
    openvpn

    cifs-utils
    nfs-utils
    usbutils

    p7zip
    unzip

    nmap
    fuse
    bind

    coreutils
    findutils
    diffutils
    gnumake
    pcsc-tools
    glibc
  ];

  users.users.thorn.shell = pkgs.zsh;

  users.users.thorn.extraGroups = [
    "wheel"
    "xen"
    "kvm"
    "networkmanager"
    "corectrl"
    "input"
  ];

  users.users.thorn.packages = with pkgs; [
    tree
    btop
    gtop
    mpv
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-mono
  ];

  services.comin = {
    enable = true;
    repositorySubdir = "./nixos";
    remotes = [
      {
        name = "origin";
        url = "https://github.com/GuildedThorn/ThornixOS.git";
        branches.main.name = "main";
      }
    ];
  };

  programs.zsh.enable = true;

  stylix.enable = true;
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/kanagawa.yaml";

  boot.kernelPackages = pkgs.linuxPackages;
}
