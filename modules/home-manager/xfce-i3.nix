{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      inputs,
      ...
    }:
    let
      cfg = config.thorn.desktop.xfceI3;
      screenshotDir = "/home/thorn/Pictures/screenshots";
      wallpaper = "${inputs.self}/users/thorn/pictures/FullLogo.png";
    in
    {
      options.thorn.desktop.xfceI3.enable = lib.mkEnableOption "XFCE + i3 Home Manager configuration";

      config = lib.mkIf cfg.enable {
        xsession.enable = true;

        home.packages = with pkgs; [
          dunst
          i3lock
          networkmanagerapplet
          picom
          playerctl
          brightnessctl
          rofi-obsidian
          xfce4-clipman-plugin
          xfce4-power-manager
          xfce4-screenshooter
        ];

        home.file."Pictures/screenshots/.keep".text = "";

        xdg.configFile."i3/config".text = ''
          set $mod Mod4
          set $terminal ghostty +new-window
          set $menu rofi -show drun
          set $window_picker rofi -show window
          set $obsidian_picker rofi -modi 'obsidian:rofi-obsidian' -show obsidian
          set $lock i3lock -c 1f1f28
          set $shots ${screenshotDir}

          font pango:GeistMono Nerd Font 10
          floating_modifier $mod
          workspace_auto_back_and_forth yes
          focus_follows_mouse no
          mouse_warping none

          default_border pixel 2
          default_floating_border pixel 2
          hide_edge_borders smart
          gaps inner 6
          gaps outer 10
          smart_gaps off

          exec_always --no-startup-id feh --bg-fill ${wallpaper}
          exec --no-startup-id xfsettingsd --replace
          exec --no-startup-id xfce4-power-manager
          exec --no-startup-id nm-applet
          exec --no-startup-id xfce4-clipman
          exec --no-startup-id dunst
          exec --no-startup-id picom --config ~/.config/picom/picom.conf

          assign [class="^Firefox$"] workspace number 1
          assign [class="^qutebrowser$"] workspace number 1
          assign [class="^Thunderbird$"] workspace number 3
          assign [class="^Code$"] workspace number 4
          assign [class="^obsidian$"] workspace number 4
          assign [class="^Obsidian$"] workspace number 4

          for_window [window_role="pop-up"] floating enable
          for_window [window_type="dialog"] floating enable
          for_window [class="^Pavucontrol$"] floating enable
          for_window [class="^Nm-connection-editor$"] floating enable
          for_window [class="^Xfce4-power-manager-settings$"] floating enable

          bindsym $mod+Return exec $terminal
          bindsym $mod+c exec gnome-calculator
          bindsym $mod+v exec thunderbird
          bindsym $mod+b exec firefox
          bindsym $mod+q kill
          bindsym $mod+Shift+Tab workspace prev
          bindsym $mod+Tab workspace next
          bindsym $mod+Right focus right
          bindsym $mod+Left focus left
          bindsym $mod+Up focus up
          bindsym $mod+Down focus down
          bindsym $mod+Shift+Right move right
          bindsym $mod+Shift+Left move left
          bindsym $mod+Shift+Up move up
          bindsym $mod+Shift+Down move down
          bindsym $mod+Ctrl+Left resize shrink width 20 px or 20 ppt
          bindsym $mod+Ctrl+Right resize grow width 20 px or 20 ppt
          bindsym $mod+Ctrl+Up resize shrink height 20 px or 20 ppt
          bindsym $mod+Ctrl+Down resize grow height 20 px or 20 ppt
          bindsym $mod+s exec $window_picker
          bindsym $mod+d exec $menu
          bindsym $mod+o exec $obsidian_picker
          bindsym $mod+Shift+F1 layout tabbed
          bindsym $mod+Shift+F2 layout toggle split
          bindsym $mod+Shift+F4 layout stacking
          bindsym XF86MonBrightnessUp exec brightnessctl set +5%
          bindsym XF86MonBrightnessDown exec brightnessctl set 5%-
          bindsym XF86AudioPlay exec playerctl play-pause
          bindsym XF86AudioNext exec playerctl next
          bindsym XF86AudioPrev exec playerctl previous
          bindsym XF86AudioMute exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
          bindsym XF86AudioRaiseVolume exec wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
          bindsym XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
          bindsym XF86AudioMicMute exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
          bindsym XF86Calculator exec gnome-calculator
          bindsym Print exec xfce4-screenshooter -f -s ${screenshotDir}
          bindsym $mod+Print exec xfce4-screenshooter -w -s ${screenshotDir}
          bindsym $mod+Shift+Print exec xfce4-screenshooter -r -s ${screenshotDir}
          bindsym $mod+l exec $lock
          bindsym $mod+f fullscreen toggle

          set $ws1 1
          set $ws2 2
          set $ws3 3
          set $ws4 4
          set $ws5 5
          set $ws6 6
          set $ws7 7
          set $ws8 8
          set $ws9 9

          bindsym $mod+1 workspace number $ws1
          bindsym $mod+2 workspace number $ws2
          bindsym $mod+3 workspace number $ws3
          bindsym $mod+4 workspace number $ws4
          bindsym $mod+5 workspace number $ws5
          bindsym $mod+6 workspace number $ws6
          bindsym $mod+7 workspace number $ws7
          bindsym $mod+8 workspace number $ws8
          bindsym $mod+9 workspace number $ws9

          bindsym $mod+Shift+1 move container to workspace number $ws1
          bindsym $mod+Shift+2 move container to workspace number $ws2
          bindsym $mod+Shift+3 move container to workspace number $ws3
          bindsym $mod+Shift+4 move container to workspace number $ws4
          bindsym $mod+Shift+5 move container to workspace number $ws5
          bindsym $mod+Shift+6 move container to workspace number $ws6
          bindsym $mod+Shift+7 move container to workspace number $ws7
          bindsym $mod+Shift+8 move container to workspace number $ws8
          bindsym $mod+Shift+9 move container to workspace number $ws9

          bar {
            mode dock
            position top
            status_command i3status
            tray_output primary
            workspace_buttons yes
          }
        '';

        xdg.configFile."picom/picom.conf".text = ''
          backend = "glx";
          vsync = true;

          shadow = true;
          shadow-radius = 16;
          shadow-offset-x = -8;
          shadow-offset-y = -8;
          shadow-opacity = 0.25;

          fading = true;
          fade-delta = 4;

          corner-radius = 12;
          round-borders = 1;

          blur-method = "dual_kawase";
          blur-strength = 6;

          inactive-opacity = 1.0;
          active-opacity = 1.0;

          rounded-corners-exclude = [
            "window_type = 'dock'"
            "class_g = 'i3-frame'"
          ];

          blur-background-exclude = [
            "window_type = 'dock'"
            "class_g = 'i3-frame'"
            "class_g = 'xfce4-panel'"
          ];

          wintypes: {
            dock = { shadow = false; clip-shadow-above = true; };
          };
        '';

        xdg.configFile."dunst/dunstrc".text = ''
          [global]
          follow = mouse
          width = 360
          height = 300
          origin = top-right
          offset = 10x10
          notification_limit = 8
          progress_bar = true
          icon_position = left
          min_icon_size = 32
          max_icon_size = 64
          padding = 12
          horizontal_padding = 20
          frame_width = 2
          corner_radius = 8
          separator_height = 2
          font = GeistMono Nerd Font 10
          markup = full
          format = "<b>%s</b>\n%b"
          default_timeout = 5s

          [urgency_low]
          timeout = 3s

          [urgency_normal]
          timeout = 5s

          [urgency_critical]
          timeout = 0
        '';
      };
    };
}
