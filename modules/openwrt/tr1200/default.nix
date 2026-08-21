{ inputs, ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, system, ... }:
    let
      profiles = inputs.openwrt-imagebuilder.lib.profiles { inherit pkgs; };

      # The release can be overridden without editing the repository:
      # nix build .#TR1200 --override-input openwrt-imagebuilder ...
      router = profiles.identifyProfile "cudy_tr1200-v1" // {
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
