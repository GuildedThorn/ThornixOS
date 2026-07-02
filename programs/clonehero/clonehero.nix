{ pkgs, ... }:

let
  # List your songs here
  songs = [
    {
      name = "Song1";
      url = "https://example.com/song1.zip";
      sha = "<sha256-1>";
    }
    {
      name = "Song2";
      url = "https://example.com/song2.zip";
      sha = "<sha256-2>";
    }
  ];

  # Build each song derivation
  songPackages = builtins.map (
    s:
    pkgs.stdenv.mkDerivation {
      pname = s.name;
      version = "1.0";
      src = pkgs.fetchzip {
        url = s.url;
        sha256 = s.sha;
      };
      installPhase = ''
        mkdir -p $out
        unzip $src -d $out
      '';
    }
  ) songs;

  # Combine all songs into a single folder
  allSongs = pkgs.buildEnv {
    name = "clonehero-songs";
    paths = songPackages;
  };
in
{
  environment.systemPackages = with pkgs; [
    allSongs
  ];

  # Set CH_SONGS_DIR so Clone Hero automatically finds songs in the Nix store
  environment.variables = {
    CH_SONGS_DIR = "${allSongs}";
  };
}
