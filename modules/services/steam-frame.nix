{
  nixos.modules.services-steam-frame =
    {
      lib,
      pkgs,
      ...
    }:

    let
      # Runtime helper that clears the driver's inactive-power-save bit each
      # time the adapter enumerates. Kept in a separate file so it can be read
      # and tested on its own.
      tuneScript = pkgs.writeShellApplication {
        name = "steam-frame-dongle-tune";
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
          iw
          util-linux
        ];
        text = builtins.readFile ./steam-frame/dongle-tune.sh;
      };
    in
    {
      # ---------------------------------------------------------------------
      # Steam Frame wireless adapter (USB 28de:2432, RTL8852CU)
      # ---------------------------------------------------------------------
      #
      # The host reaches the headset through the adapter acting as a Wi-Fi
      # client of the headset's 6 GHz access point (SSID frame_XXXXXXXX,
      # 10.35.78.0/24); Steam Link / Remote Play then runs over that link.
      #
      # The stock rtw89 driver does not handle this adapter well:
      #
      #   * it transmits on 2.4 GHz during every scan, and doing so drops the
      #     adapter's USB 3 link. It re-enumerates with RTNL held, which freezes
      #     the desktop for 10-17 s, and the driver eventually reports the phy
      #     as hard rfkill-blocked. The headset never needs 2.4 GHz, so turning
      #     that band off removes the trigger entirely (steam-for-linux#13643).
      #
      #   * it adopts the AP's advertised 6 GHz power class, which for the
      #     headset's "very low power" beacon leaves roughly 2 dBm per chain.
      #     Forcing LPI gives the link usable range and stops the stutter.
      #
      #   * it enters an inactive power state between scans; waking it blocks on
      #     the USB bus for seconds. Both the disable_ps_mode module parameter
      #     and the runtime disable_dm bitmap keep that path out of play.
      #
      # Two small in-tree patches add disable_2ghz and reg6_pwr_override; the
      # rest is module parameters, NetworkManager defaults and a udev oneshot.
      # Everything is local to this repo - no upstream flake is imported.

      # Match the headset's regulatory domain. The host otherwise stays on the
      # world domain ("00") and the driver refuses to use the 6 GHz channels the
      # headset's access point lives on.
      boot.kernelParams = [ "cfg80211.ieee80211_regdom=US" ];

      boot.kernelPatches = [
        {
          name = "rtw89-steam-frame-reg6-pwr-override";
          patch = ./steam-frame/0001-rtw89-reg6-pwr-override.patch;
        }
        {
          name = "rtw89-steam-frame-disable-2ghz";
          patch = ./steam-frame/0002-rtw89-disable-2ghz.patch;
        }
        {
          # Exposes /sys/kernel/debug/ieee80211/<phy>/rtw89/disable_dm, which
          # the tuning oneshot writes to. It depends on CFG80211_DEBUGFS, which
          # the NixOS kernel already builds in.
          name = "rtw89-debugfs";
          patch = null;
          structuredExtraConfig.RTW89_DEBUGFS = lib.kernel.yes;
        }
      ];

      boot.extraModprobeConfig = ''
        # Steam Frame wireless adapter. The headset's access point uses the US
        # regulatory domain, so make the host agree even if the kernel command
        # line parameter is ignored because cfg80211 is a loadable module.
        options cfg80211 ieee80211_regdom=US

        # reg6_pwr_override: -1 follow the AP (default), 0 VLP, 1 LPI, 2 SP.
        # LPI lifts the transmit power the driver derives from the headset's
        # low-power beacon.
        #
        # disable_2ghz: never scan or transmit on 2.4 GHz. That band is what
        # makes the adapter reset its USB link; the headset is 6 GHz only.
        #
        # disable_ps_mode: keep the chip out of low-power mode, which otherwise
        # costs seconds per scan while it wakes up.
        options rtw89_core reg6_pwr_override=1 disable_2ghz=Y disable_ps_mode=Y
      '';

      networking.networkmanager = {
        wifi = {
          # Every MAC change forces an interface down/up, and this chip then
          # re-initialises over USB for 10-15 s with RTNL held. Keep the
          # permanent MAC and stop scan-time randomisation as well.
          macAddress = "permanent";
          scanRandMacAddress = false;

          # Inactive power save wakes the chip on every scan; disable Wi-Fi
          # powersave globally (this host has no other Wi-Fi interface).
          powersave = false;
        };

        settings."connection-steam-frame-dongle" = {
          match-device = "driver:rtw89_8852cu";

          # The headset link is a direct 10.35.78.0/24 network next to the
          # wired uplink. It must never become the default route or replace the
          # fleet DNS servers, and it should lose to ethernet on equal routes.
          "ipv4.never-default" = true;
          "ipv4.ignore-auto-dns" = true;
          "ipv4.route-metric" = 700;
        };
      };

      services.udev.extraRules = ''
        # Never runtime-suspend the Steam Frame adapter: a resumed USB link is
        # what the driver spends seconds re-initialising.
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2432", TEST=="power/control", ATTR{power/control}="on"

        # Clear rtw89 inactive power save whenever the netdev appears. udev
        # hands the work to systemd because debugfs for the new phy is not
        # ready inside the udev worker.
        ACTION=="add", SUBSYSTEM=="net", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2432", TAG+="systemd", ENV{SYSTEMD_WANTS}+="steam-frame-dongle-tune@%k.service"
      '';

      systemd.services."steam-frame-dongle-tune@" = {
        description = "Disable rtw89 inactive power save for the Steam Frame dongle (%I)";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe tuneScript + " %I";
        };
      };

      # The headset lives on a second, directly attached network while the
      # default route stays on ethernet. Strict reverse-path filtering drops
      # that traffic on a multi-homed host.
      networking.firewall.checkReversePath = "loose";

      # Steam Link / Remote Play discovery and streaming ports.
      programs.steam.remotePlay.openFirewall = true;

      environment.systemPackages = with pkgs; [
        iw
        libva-utils
      ];

      # Exposed so CI can build the tuning helper with the host closure.
      system.build.steamFrameDongleTune = tuneScript;
    };
}
