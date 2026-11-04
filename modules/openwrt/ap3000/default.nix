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
        "https://downloads.openwrt.org/releases/25.12.6/packages/aarch64_cortex-a53/base/packages.adb" =
          "sha256-e/3688us45+OalO9cK1xEIFpC7JyIbdstzBaGaldFIU=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/aarch64_cortex-a53/luci/packages.adb" =
          "sha256-nTuHyAjVQM5xLYVZyKtF3tchpUgLC9QyfFp0kLnRN98=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/aarch64_cortex-a53/packages/packages.adb" =
          "sha256-v/8kZVyoWx8jCbsXcC09vuqRbupfOJkgZ2sUI+zmAjE=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/aarch64_cortex-a53/routing/packages.adb" =
          "sha256-oqYA4BIiaUHeZ6meZnPhUfwpRRq8LwoZAM+z7bD2J/E=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/aarch64_cortex-a53/telephony/packages.adb" =
          "sha256-8T/o/dgIOBYw2a1yuGvDUO+UHJNnCpLvf4yybZmHuCk=";
        "https://downloads.openwrt.org/releases/25.12.6/packages/aarch64_cortex-a53/sha256sums" =
          "sha256-/01zDyLGbKE6pQdmE5wbCYWDbiJrWtXnixtOENsIjQM=";
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
      # nix build .#AP3000 --override-input openwrt-imagebuilder ...
      accessPoint = profiles.identifyProfile "cudy_ap3000-v1" // {
        inherit fetchurl;
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
