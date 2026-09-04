{ inputs, ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, system, ... }:
    let
      profiles = inputs.openwrt-imagebuilder.lib.profiles { inherit pkgs; };

      # The release can be overridden without editing the repository:
      # nix build .#AP3000 --override-input openwrt-imagebuilder ...
      accessPoint = profiles.identifyProfile "cudy_ap3000-v1" // {
        packages = [
          # The basic variant conflicts with wpad-mesh-mbedtls. Replace it to
          # retain normal AP support while adding encrypted 802.11s backhaul.
          "-wpad-basic-mbedtls"
          "wpad-mesh-mbedtls"

          # Distributed roaming assistance for wired or wireless AP nodes.
          "usteer"
          "luci-app-usteer"

          # HTTPS management, topology discovery, and AP diagnostics.
          "luci-ssl"
          "lldpd"
          "luci-app-lldpd"
          "tcpdump-mini"
          "iperf3"
        ];

        # Keep optional policy services dormant until SSIDs and backhaul are
        # configured. Normal AP and 802.11s support remains available in wpad.
        disabledServices = [
          "radius"
          "usteer"
        ];

        extraImageName = "AP3000";
      };
    in
    {
      # The upstream ImageBuilder is x86_64-linux only.
      packages = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
        AP3000 = inputs.openwrt-imagebuilder.lib.build accessPoint;
      };
    };
}
