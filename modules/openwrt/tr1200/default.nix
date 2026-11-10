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
        "https://downloads.openwrt.org/releases/25.12.6/packages/mipsel_24kc/base/packages.adb" =
          "sha256-GscOYfNzLxiH18f84UDNaENVSuhyTPqaqAStBEz3r7k=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/mipsel_24kc/luci/packages.adb" =
          "sha256-F3Nw1nsCPnyYNLk3J1wLFyijclnRoQzDw/krQaak8x8=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/mipsel_24kc/packages/packages.adb" =
          "sha256-UpVEwF3dF/GWfgl8bR7VCWCReLBNCmGAvoCs3kFmS2s=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/mipsel_24kc/routing/packages.adb" =
          "sha256-k0eLTbeFWFh1MZXjVslNZbJSYxunaDCiQDw/6TG1Tv8=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/mipsel_24kc/telephony/packages.adb" =
          "sha256-5fD3nbRiax9ByCul6imUEDEs4imhm2TZyTbaIZ29GVM=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/mipsel_24kc/sha256sums" =
          "sha256-Lvq6lAWKgZkJhbEMKql8kf4cIFUVv38mB1V3uvoFwlU=";
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
