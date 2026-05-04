{
  pkgs,
  lib,
  inputs,
  ...
}:
{

  imports = [
    ./networking.nix

    "${inputs.self}/processor/intel.nix"
    "${inputs.self}/graphics/intel.nix"
    "${inputs.self}/desktop/hyprland.nix"

    "${inputs.self}/services/audio.nix"
    "${inputs.self}/services/bluetooth.nix"
    "${inputs.self}/services/clamav.nix"
    "${inputs.self}/services/fingerprint.nix"
    "${inputs.self}/services/keybase.nix"
    "${inputs.self}/services/obs.nix"
    "${inputs.self}/services/spicetify.nix"
    "${inputs.self}/services/sdr.nix"
    "${inputs.self}/services/ssh.nix"

    "${inputs.self}/users/thorn/services/glance.nix"
  ];

  home-manager.users.thorn = import ./home.nix;

  environment.systemPackages = with pkgs; [
    networkmanager

    corectrl

    openrgb

    nwg-displays
    nwg-look

    glance

    wev
    brightnessctl

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
    piper

    rofi-obsidian

    chirp

    codex

    postman
    mongodb-compass

    keepassxc

    system-config-printer

    android-studio
    android-tools

    easyeffects
    mixxx
    musescore
    hydrogen
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  services.printing = {
    enable = true;
    drivers = with pkgs; [
      cups-filters
      cups-browsed
      gutenprint
      canon-cups-ufr2
    ];
  };

  boot.kernelParams = [ "acpi_backlight=native" ];

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

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  services.gvfs.enable = true;
  services.udisks2.enable = true;

  services.upower.enable = true;

  services.howdy.enable = true;
  services.linux-enable-ir-emitter.enable = true;

  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 20;

      # Optional helps save long term battery health
      START_CHARGE_THRESH_BAT0 = 75; # 40 and below it starts to charge
      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
    };
  };

  services.thinkfan = {
    enable = true;

    sensors = [
      {
        query = "/proc/acpi/ibm/thermal";
        type = "tpacpi";
      }
    ];

    fans = [
      {
        query = "/proc/acpi/ibm/fan";
        type = "tpacpi";
      }
    ];

    # Aggressive fan curve
    levels = [
      [
        0
        0
        35
      ]
      [
        1
        33
        40
      ]
      [
        2
        38
        45
      ]
      [
        3
        43
        50
      ]
      [
        4
        48
        55
      ]
      [
        5
        53
        60
      ]
      [
        6
        58
        65
      ]
      [
        7
        63
        70
      ]
      [
        7
        68
        32767
      ] # full blast above ~68°C
    ];
  };

  services.thermald.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
  };

  security.polkit.enable = true;

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
  security.pam.howdy.enable = true;

  security.pam.services.greetd.howdy.control = "sufficient";

  security.pam.services.sudo.rules.auth.howdy.control = lib.mkForce "sufficient";

}
