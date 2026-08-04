{
  # Reproducible, local-only IP geolocation data for Alloy pipelines. The
  # databases are public data, not secrets, and are pinned like every other
  # build input so a deploy never performs a runtime lookup or download.
  nixos.modules.services-geoip =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.geoip;
      release = "2026-08";

      cityArchive = pkgs.fetchurl {
        url = "https://download.db-ip.com/free/dbip-city-lite-${release}.mmdb.gz";
        hash = "sha256-K1MgPsNql1BRqBidwSB9Yk47wwL77kdkiShHZTO+adE=";
      };
      asnArchive = pkgs.fetchurl {
        url = "https://download.db-ip.com/free/dbip-asn-lite-${release}.mmdb.gz";
        hash = "sha256-EraUoa7u7j2HR4aC+omhquQ4affDMmTHUV/R+SmSAT4=";
      };

      unpackMmdb = name: archive:
        pkgs.runCommand name
          {
            nativeBuildInputs = [ pkgs.gzip ];
            meta.license = lib.licenses.cc-by-40;
          }
          ''
            gzip -dc ${archive} > "$out"
          '';

      cityDatabase = unpackMmdb "dbip-city-lite-${release}.mmdb" cityArchive;
      asnDatabase = unpackMmdb "dbip-asn-lite-${release}.mmdb" asnArchive;
    in
    {
      options.thorn.geoip.enable = lib.mkEnableOption "local DB-IP City and ASN MMDB databases";

      config = lib.mkIf cfg.enable {
        # Stable local paths keep Alloy configuration readable. These are
        # immutable symlinks into the Nix store, so Alloy only needs read
        # access and a compromised collector cannot poison future lookups.
        environment.etc = {
          "GeoIP/DBIP-City-Lite.mmdb".source = cityDatabase;
          "GeoIP/DBIP-ASN-Lite.mmdb".source = asnDatabase;
          "GeoIP/DB-IP-LITE-NOTICE".text = ''
            DB-IP Lite City and ASN databases, release ${release}
            Copyright (c) DB-IP.com
            Licensed under Creative Commons Attribution 4.0 International.
            IP Geolocation by DB-IP: https://db-ip.com/db/lite.php
          '';
        };
      };
    };
}
