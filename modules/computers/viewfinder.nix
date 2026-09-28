{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/viewfinder/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.viewfinder = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-interactive
      inputs.sc0710.nixosModules.default
      config.nixos.modules.hardware-sc0710-firmware

      config.nixos.modules.desktop-hyprland
      config.nixos.modules.processor-amd
      config.nixos.modules.graphics-nvidia

      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-capture-card
      config.nixos.modules.services-clamav
      config.nixos.modules.services-flare-agent
      config.nixos.modules.services-flare-lab
      config.nixos.modules.services-obs
      config.nixos.modules.services-proxmox
      config.nixos.modules.services-spicetify
      config.nixos.modules.services-ssh
      config.nixos.modules.services-zeek

      config.nixos.modules.hardware-viewfinder
      "${inputs.self}/hosts/viewfinder/disko.nix"
      "${inputs.self}/hosts/viewfinder/flare-lab.nix"
      "${inputs.self}/hosts/viewfinder/networking.nix"
      "${inputs.self}/hosts/viewfinder/secrets.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/viewfinder/home.nix"; }

      (
        {
          config,
          pkgs,
          lib,
          ...
        }:
        {
          hardware.sc0710.enable = true;

          # sc0710 supports kernels up to 7.0, and 7.0 is EOL in nixpkgs, so
          # pin the boot kernel to 6.18 (same line the installer boots).
          boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_18;

          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;
          boot.initrd.systemd.enable = true;

          # Keep the workstation desktop native while exposing this machine
          # as a small Proxmox node alongside it.
          boot.kernelModules = [ "kvm-amd" ];

          services.proxmox-ve = {
            ipAddress = "172.16.25.103";
            bridges = [
              "vmbr0"
              "vmbr1"
            ];
          };

          # Passive sensor for the isolated detonation segment. vmbr1 has no
          # physical uplink and no gateway, so this captures everything the
          # analysis VMs do on 10.77.0.0/24 and nothing else. No capture
          # filter is needed because this host's Alloy shipping to the SOC
          # leaves over vmbr0 and is never seen on this interface.
          #
          # The lab profile keeps conn/DNS/HTTP/file/TLS-SNI logs and drops the
          # SSH-bruteforce and TLS-validation notice sources, which would
          # otherwise fire continuously against deliberately hostile traffic.
          # The live topology graph is left off: its purpose is modelling
          # production assets, and a detonation VM has no stable identity.
          thorn.zeek = {
            enable = true;
            profile = "lab";
            interface = "vmbr1";
            localNetworks = [ "10.77.0.0/24" ];
            topology.enable = false;
          };

          # The Elgato 4K Capture Pro is a PCIe card, and Discord on Linux
          # (Vesktop) has no equivalent of Windows' "Capture Devices" source,
          # while the Hyprland share picker only offers outputs, windows and
          # regions. So the card is surfaced as an mpv window and that window is
          # what gets shared. It is drawn on a headless output, so it is never
          # visible on either display.
          thorn.captureCard.enable = true;

          boot.extraModulePackages = with config.boot.kernelPackages; [
            nvidia_x11
          ];

          nixpkgs.overlays = [
            (final: prev: {
              # Hyprland's pinned guiutils build is evaluated against the
              # nixpkgs package set, so follow the compatible utility input
              # here as well as in the flake input graph.
              hyprutils = inputs.hyprutils-guiutils.packages.${final.system}.default;
              # The NixOS Hyprland module adds this package from nixpkgs to
              # the system path; select the flake build whose toolkit and
              # utility inputs are already compatible.
              hyprland-guiutils = inputs.hyprland-guiutils.packages.${final.system}.default;
              obs-studio = prev.obs-studio.override {
                ffmpeg = prev.ffmpeg-full;
                cudaSupport = true;
              };
            })
          ];

          environment.systemPackages = with pkgs; [
            v4l-utils
            ffmpeg
            nwg-displays
            ghostty

            # GPU hash-cracking host: this box's RTX 2070 is one of the two GPUs
            # driven by the Hashtopolis agents. Hashtopolis ships its own
            # hashcat for agent work; these are for manual CLI use.
            hashcat
            john
          ];

          users = {
            users = {
              root = {
                initialHashedPassword = "!";
                openssh.authorizedKeys.keys = adminSshKeys;
              };
              thorn = {
                openssh.authorizedKeys.keys = adminSshKeys;
              };
            };
          };

          zramSwap = {
            enable = true;
            memoryPercent = 25;
          };

          security.rtkit.enable = true;

          services.earlyoom.enable = true;
          services.fwupd.enable = true;
        }
      )
    ];
  };
}
