{ inputs, ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, system, ... }:
    let
      profiles = inputs.openwrt-imagebuilder.lib.profiles { inherit pkgs; };

      # OpenWrt regenerates signed package indexes after release. Override the
      # ImageBuilder cache's stale index hashes while package payload hashes
      # remain pinned by the release's sha256sums files.
      refreshedIndexHashes = {
        "https://downloads.openwrt.org/releases/25.12.5/packages/mipsel_24kc/base/packages.adb" =
          "sha256-5UB86Q8yMVUV8SWJ4kU7TcitIl0Yo+SdX3vj9nQdVvI=";
        "https://downloads.openwrt.org/releases/25.12.5/packages/mipsel_24kc/luci/packages.adb" =
          "sha256-34ijlOuARFirq6tgsvn5aCVBvUny7Go1GHf/IEdVIwI=";
        "https://downloads.openwrt.org/releases/25.12.5/packages/mipsel_24kc/packages/packages.adb" =
          "sha256-mio0fn838g8NMxGXyihLOnRXmFzyFy1cO0d8KLwPMtI=";
        "https://downloads.openwrt.org/releases/25.12.5/packages/mipsel_24kc/routing/packages.adb" =
          "sha256-EP6PDZmCZ2Opus4+56IswVQtkjcQucyQOrS2yq03rYs=";
        "https://downloads.openwrt.org/releases/25.12.5/packages/mipsel_24kc/telephony/packages.adb" =
          "sha256-rNmvZE/jlEOk+YQ770gexEgF/5FOfxfgejErQ57AHpo=";
        "https://downloads.openwrt.org/releases/25.12.5/packages/mipsel_24kc/sha256sums" =
          "sha256-tcG2rY0ZgkyoLDa59rDMG5sGvznS91kvxfKrIYyZfnE=";
      };
      fetchurl =
        args:
        pkgs.fetchurl (
          args
          // pkgs.lib.optionalAttrs (builtins.hasAttr args.url refreshedIndexHashes) {
            hash = refreshedIndexHashes.${args.url};
          }
        );

      # The release can be overridden without editing the repository:
      # nix build .#TR1200 --override-input openwrt-imagebuilder ...
      router = profiles.identifyProfile "cudy_tr1200-v1" // {
        inherit fetchurl;
        packages = [
          # WireGuard client support and LuCI integration.
          "kmod-wireguard"
          "wireguard-tools"
          "luci-proto-wireguard"

          # Travelmate and its LuCI application. Package dependencies are
          # resolved by the OpenWrt ImageBuilder.
          "travelmate"
          "luci-app-travelmate"

          # HTTPS LuCI plus certificates/curl for captive portal handling.
          "luci-ssl"
          "ca-bundle"
          "curl"
          "qrencode"
        ];

        files = ./files;
        extraImageName = "TR1200";
      };
    in
    {
      # The upstream ImageBuilder is x86_64-linux only.
      packages = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
        TR1200 = inputs.openwrt-imagebuilder.lib.build router;
      };
    };
}
