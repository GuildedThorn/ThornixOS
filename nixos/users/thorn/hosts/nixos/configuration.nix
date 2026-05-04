{
  pkgs,
  inputs,
  ...
}:
{

  imports = [
    ./networking.nix

    "${inputs.self}/desktop/hyprland.nix"
    "${inputs.self}/processor/amd.nix"
    "${inputs.self}/graphics/amd.nix"

    "${inputs.self}/services/audio.nix"
    "${inputs.self}/services/bluetooth.nix"
    "${inputs.self}/services/clamav.nix"
    "${inputs.self}/services/displaylink.nix"
    "${inputs.self}/services/fingerprint.nix"
    "${inputs.self}/services/keybase.nix"
    #"${inputs.self}/services/proxmox.nix"
    "${inputs.self}/services/obs.nix"
    #"${inputs.self}/services/ollama.nix"
    "${inputs.self}/services/retroarch.nix"
    "${inputs.self}/services/spicetify.nix"
    "${inputs.self}/services/sdr.nix"
    "${inputs.self}/services/ssh.nix"
    "${inputs.self}/services/steam.nix"
    "${inputs.self}/services/tablets.nix"
    "${inputs.self}/services/vmware.nix"
    "${inputs.self}/services/vr.nix"

    "${inputs.self}/users/thorn/services/glance.nix"
  ];

  home-manager.users.thorn = import ./home.nix;

  environment.systemPackages = with pkgs; [
    kitty

    corectrl

    openrgb

    displaylink

    nwg-displays
    nwg-look

    glance

    tradingview
    grisbi

    komikku
    jellyfin-desktop

    teamspeak6-client
    element-desktop
    telegram-desktop

    blender

    krita

    kdePackages.kdenlive

    orca-slicer

    fritzing

    plasticity

    ethtool

    steam
    steam-run
    steamcmd

    oversteer
    piper

    lutris
    heroic

    osu-lazer-bin
    clonehero

    retroarch
    libretro.pcsx-rearmed
    libretro.pcsx2

    rofi-obsidian

    chirp

    arduino
    arduino-ide

    codex
    claude-code

    distrobox

    jetbrains.rider

    postman
    mongodb-compass

    virt-viewer
    realvnc-vnc-viewer

    vmware-workstation

    keepassxc

    system-config-printer

    android-studio
    android-tools

    mixxx
    musescore
    hydrogen

    openxr-loader
    xrizer
    wayvr
  ];

  virtualisation.waydroid.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  services.printing = {
    enable = true;
    drivers = with pkgs; [
      cups-filters
      cups-browsed
      gutenprint
      canon-cups-ufr2
    ];
  };

  services.hardware.openrgb = {
    enable = true;
    package = pkgs.openrgb-with-all-plugins;
  };

  programs.npm.enable = true;

  programs.corectrl = {
    enable = true;
  };

  programs.thunar.enable = true;
  programs.thunar.plugins = with pkgs; [
    thunar-archive-plugin
    thunar-volman
  ];

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.starship = {
    enable = true;
  };

  programs.thunderbird = {
    enable = true;
    package = pkgs.thunderbird;

    # Enterprise-style policies
    policies = {
      DisableAppUpdate = true;
      DisableTelemetry = true;
    };
  };

  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  programs.seahorse.enable = true;
  programs.dconf.enable = true;

  programs.steam.remotePlay.openFirewall = true;

  hardware.gpgSmartcards.enable = true;

  services.ananicy.enable = true;

  services.earlyoom.enable = true;

  services.fwupd.enable = true;

  services.ratbagd.enable = true;

  services.pcscd.enable = true;
  services.pcscd.plugins = [ pkgs.ccid ];

  services.flatpak.enable = true;

  systemd.oomd.enable = true;

  services.dbus.enable = true;

  services.udev.packages = with pkgs; [
    yubikey-personalization
  ];

  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  services.gvfs.enable = true;
  services.udisks2.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
  };

  security.polkit.enable = true;
  security.rtkit.enable = true;

  services.ollama.package = pkgs.ollama-vulkan;

  security.pam.u2f = {
    enable = true;
    control = "sufficient";

    settings = {
      cue = true;
      interactive = true;
    };
  };

  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "8G";

  security.pam.services.sddm.u2fAuth = true;
  security.pam.services.sudo.u2fAuth = true;

}
