{ config, inputs, ... }:
let
  homeManagerThorn = config.homeManager.modules.thorn;
in
{
  nixos.modules.thorn-user =
    { pkgs, ... }:
    {

      home-manager.users.thorn = homeManagerThorn;

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
        (builtins.readFile "${inputs.self}/certs/ThornCloud_CA.crt")
      ];

      security.pam.services.login.enableGnomeKeyring = true;

      environment.systemPackages = with pkgs; [
        tree-sitter

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
        ripdrag
        findutils
        diffutils
        gnumake
        pcsc-tools
        glibc

        wev
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

      fonts = {
        enableDefaultPackages = true;

        packages = with pkgs; [
          geist-font
          noto-fonts-color-emoji

          nerd-fonts.geist-mono
        ];

        fontconfig = {
          enable = true;

          defaultFonts = {
            sansSerif = [ "Geist" ];
            serif = [ "Geist" ];
            monospace = [ "GeistMono Nerd Font" ];
            emoji = [ "Noto Color Emoji" ];
          };

          # Optional but usually nice
          hinting = {
            enable = true;
            style = "slight";
          };

          subpixel = {
            rgba = "rgb";
            lcdfilter = "default";
          };
        };
      };

      #services.kmscon.enable = true;

      services.comin = {
        enable = true;
        desktop.enable = true;
        remotes = [
          {
            name = "origin";
            url = "https://github.com/GuildedThorn/ThornixOS.git";
            branches.main.name = "main";
          }
        ];
      };

      programs.zsh.enable = true;

      stylix = {
        enable = true;
        base16Scheme = "${pkgs.base16-schemes}/share/themes/kanagawa.yaml";
        fonts = {
          sansSerif = {
            package = pkgs.geist-font;
            name = "Geist";
          };
          serif = {
            package = pkgs.geist-font;
            name = "Geist";
          };
          monospace = {
            package = pkgs.nerd-fonts.geist-mono;
            name = "GeistMono Nerd Font";
          };
          emoji = {
            package = pkgs.noto-fonts-color-emoji;
            name = "Noto Color Emoji";
          };
        };
      };

      boot = {
        plymouth = {
          enable = true;
        };

        # Enable "Silent boot"
        consoleLogLevel = 3;
        initrd.verbose = false;
        kernelParams = [
          "quiet"
          "udev.log_level=3"
          "systemd.show_status=auto"
        ];
        # Hide the OS choice for bootloaders.
        # It's still possible to open the bootloader list by pressing any key
        # It will just not appear on screen unless a key is pressed
        loader.timeout = 0;
      };
    };
}
