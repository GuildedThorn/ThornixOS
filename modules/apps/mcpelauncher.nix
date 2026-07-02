{
  nixos.modules.apps-mcpelauncher =
    { pkgs, ... }:
    let
      pname = "mcpelauncher-ui-qt";
      version = "0.40.3";

      src = pkgs.fetchurl {
        url = "https://github.com/minecraft-linux/appimage-builder/releases/download/v1.1.1-802/Minecraft_Bedrock_Launcher-x86_64-v1.1.1.802.AppImage";
        hash = "sha256-lK7c/1ieFGOtWVU0vGKfyQJiBu8NJAQjR0DvpZUE0Ns=";
      };
      appimageContents = pkgs.appimageTools.extract { inherit pname version src; };
    in
    pkgs.appimageTools.wrapType2 {
      inherit pname version src;
      pkgs = pkgs;
      extraInstallCommands = ''
        install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
        substituteInPlace $out/share/applications/${pname}.desktop \
          --replace 'Exec=AppRun' 'Exec=${pname}'
        cp -r ${appimageContents}/usr/share/icons $out/share

        # unless linked, the binary is placed in $out/bin/cursor-someVersion
        # ln -s $out/bin/${pname}-${version} $out/bin/${pname}
      '';

      extraBwrapArgs = [
        "--bind-try /etc/nixos/ /etc/nixos/"
      ];

      dieWithParent = false;

      extraPkgs =
        pkgs: with pkgs; [
          unzip
          autoPatchelfHook
          asar
          (buildPackages.wrapGAppsHook3.override { inherit (buildPackages) makeWrapper; })
        ];
    };
}
