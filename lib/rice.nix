{
  # One visual vocabulary for the desktop shell. Keep these as bare hex
  # values so the same palette can be embedded in Rasi, GTK CSS, SCSS, and
  # Hyprlock's rgb()/rgba() syntax without each module drifting independently.
  colors = {
    rosewater = "f5e0dc";
    flamingo = "f2cdcd";
    pink = "f5c2e7";
    mauve = "cba6f7";
    red = "f38ba8";
    maroon = "eba0ac";
    peach = "fab387";
    yellow = "f9e2af";
    green = "a6e3a1";
    teal = "94e2d5";
    sky = "89dceb";
    sapphire = "74c7ec";
    blue = "89b4fa";
    lavender = "b4befe";
    text = "cdd6f4";
    subtext1 = "bac2de";
    subtext0 = "a6adc8";
    overlay2 = "9399b2";
    overlay1 = "7f849c";
    overlay0 = "6c7086";
    surface2 = "585b70";
    surface1 = "45475a";
    surface0 = "313244";
    base = "1e1e2e";
    mantle = "181825";
    crust = "11111b";
  };

  fonts = {
    sans = "Geist";
    mono = "GeistMono Nerd Font";
  };

  geometry = {
    border = 2;
    radiusSmall = 10;
    radiusMedium = 14;
    radiusLarge = 18;
  };

  cursor = {
    name = "catppuccin-mocha-mauve-cursors";
    size = 24;
  };

  # A compact mark for lifecycle surfaces. Keeping the SVG here makes the
  # exact same artwork available to both NixOS and Home Manager without a
  # mutable asset in ~/.config (and without repurposing the GuildedThorn
  # artwork in pictures/FullLogo.png as an OS logo).
  branding = rec {
    name = "THORNIX";

    svgText = ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
        <defs>
          <linearGradient id="thornix-accent" x1="96" y1="72" x2="416" y2="440" gradientUnits="userSpaceOnUse">
            <stop offset="0" stop-color="#cba6f7"/>
            <stop offset="0.55" stop-color="#b4befe"/>
            <stop offset="1" stop-color="#89b4fa"/>
          </linearGradient>
          <filter id="thornix-glow" x="-30%" y="-30%" width="160%" height="160%">
            <feGaussianBlur stdDeviation="5" result="blur"/>
            <feMerge>
              <feMergeNode in="blur"/>
              <feMergeNode in="SourceGraphic"/>
            </feMerge>
          </filter>
        </defs>

        <g fill="none" stroke="url(#thornix-accent)" stroke-linecap="round" stroke-linejoin="round">
          <path opacity="0.28" stroke-width="10" d="M256 52 397 134 397 298 256 460 115 378 115 214Z"/>
          <path opacity="0.72" stroke-width="14" d="M159 142 256 86 353 142M394 210v112l-62 71M180 420l-62-36V272"/>
          <path opacity="0.86" stroke-width="11" d="M168 168 119 127M151 153l-44 4M154 160l-25 34M344 168l49-41M361 153l44 4M358 160l25 34"/>
          <path stroke-width="18" filter="url(#thornix-glow)" d="M166 168h180M256 168v192"/>
        </g>

        <g fill="url(#thornix-accent)">
          <path d="M256 392 211 337l29 4V181h32v160l29-4Z"/>
          <circle cx="256" cy="86" r="13"/>
          <circle cx="118" cy="384" r="13"/>
          <circle cx="394" cy="322" r="13"/>
        </g>
      </svg>
    '';

    svg = pkgs: pkgs.writeText "thornix-mark.svg" svgText;

    png =
      pkgs: size:
      pkgs.runCommand "thornix-mark-${toString size}.png"
        {
          nativeBuildInputs = [ pkgs.librsvg ];
        }
        ''
          rsvg-convert \
            --width ${toString size} \
            --height ${toString size} \
            "${svg pkgs}" > "$out"
        '';
  };
}
