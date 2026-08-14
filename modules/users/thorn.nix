{ config, inputs, ... }:
let
  homeManagerThorn = config.homeManager.modules.thorn;
  fleet = import ../../hosts/inventory.nix;
  rice = import ../../lib/rice.nix;
in
{
  nixos.modules.thorn-user =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      hostName = config.networking.hostName;
      host = fleet.${hostName} or null;
      deployment = if host == null then { enable = false; } else host.deployment;
      catppuccinPlymouth = pkgs.catppuccin-plymouth.override { variant = "mocha"; };
      thornixPlymouthConfig = pkgs.writeText "thornix.plymouth" ''
        [Plymouth Theme]
        Name=thornix
        Description=Thornix Catppuccin Mocha boot sequence
        ModuleName=two-step

        [two-step]
        Font=Geist 12
        TitleFont=Geist Light 30
        ImageDir=@THEME_DIR@
        DialogHorizontalAlignment=.5
        DialogVerticalAlignment=.5
        TitleHorizontalAlignment=.5
        TitleVerticalAlignment=.5
        HorizontalAlignment=.5
        VerticalAlignment=.62
        WatermarkHorizontalAlignment=.5
        WatermarkVerticalAlignment=.42
        Transition=none
        TransitionDuration=0.0
        BackgroundStartColor=0x${rice.colors.base}
        BackgroundEndColor=0x${rice.colors.base}
        ProgressBarBackgroundColor=0x${rice.colors.surface0}
        ProgressBarForegroundColor=0x${rice.colors.mauve}
        MessageBelowAnimation=true

        [boot-up]
        UseEndAnimation=false

        [shutdown]
        UseEndAnimation=false

        [reboot]
        UseEndAnimation=false
      '';
      thornixPlymouth =
        pkgs.runCommand "thornix-plymouth-theme"
          {
            nativeBuildInputs = [ pkgs.librsvg ];
          }
          ''
            theme_dir="$out/share/plymouth/themes/thornix"
            mkdir -p "$theme_dir"
            cp ${catppuccinPlymouth}/share/plymouth/themes/catppuccin-mocha/*.png "$theme_dir/"
            cp ${thornixPlymouthConfig} "$theme_dir/thornix.plymouth"
            substituteInPlace "$theme_dir/thornix.plymouth" \
              --replace-fail '@THEME_DIR@' "$theme_dir"
            rsvg-convert --width 164 --height 164 \
              "${rice.branding.svg pkgs}" > "$theme_dir/watermark.png"
          '';
    in
    {

      assertions = [
        {
          assertion = host != null;
          message = "${hostName} is missing from hosts/inventory.nix";
        }
      ];

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

      services.comin = lib.mkIf deployment.enable {
        enable = true;
        desktop.enable = host.class == "workstation" || host.class == "laptop";
        remotes = [
          {
            name = "origin";
            url = "https://github.com/GuildedThorn/ThornixOS.git";
            # Every production host follows the same immutable promotion
            # pointer. Hydra proves the complete fleet first, and Cachix has
            # the exact closure before Forge advances this branch.
            branches.main.name = deployment.branch;
          }
        ];
      };

      programs.zsh.enable = true;

      stylix = {
        enable = true;
        base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
        cursor = {
          inherit (rice.cursor) name size;
          package = pkgs.catppuccin-cursors.mochaMauve;
        };
        targets.plymouth.enable = false;
        fonts = {
          sansSerif = {
            package = pkgs.geist-font;
            name = rice.fonts.sans;
          };
          serif = {
            package = pkgs.geist-font;
            name = rice.fonts.sans;
          };
          monospace = {
            package = pkgs.nerd-fonts.geist-mono;
            name = rice.fonts.mono;
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
          theme = "thornix";
          themePackages = [ thornixPlymouth ];
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
