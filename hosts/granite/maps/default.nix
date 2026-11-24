{ config, pkgs, ... }:
let
  dataDir = "/platter/services/reference/maps";

  planetilerJar = pkgs.fetchurl {
    url = "https://github.com/onthegomap/planetiler/releases/download/v0.10.2/planetiler.jar";
    sha256 = "0kby2rnf0gg2f0m3qq1ipz9y3s34hr0ns17l4wmm3r722c2bs47k";
  };

  maplibreJs = pkgs.fetchurl {
    url = "https://unpkg.com/maplibre-gl@5.24.1/dist/maplibre-gl.js";
    sha256 = "1jf77c1y9ynvw38xs3ncxqz8ha0s5wkw29qz2cxvdmfl6smf5jd9";
  };
  maplibreCss = pkgs.fetchurl {
    url = "https://unpkg.com/maplibre-gl@5.24.1/dist/maplibre-gl.css";
    sha256 = "0cm7szgvmvwfb6yn4bjhzlrq3wncyfi0s0z7wyx6a164kvap07mb";
  };
  pmtilesJs = pkgs.fetchurl {
    url = "https://unpkg.com/pmtiles@4.5.0/dist/pmtiles.js";
    sha256 = "0v2caldw5468qpa2pjpdc2gscf4xv1jcjpaxwvkpwcpn8sy83yfa";
  };

  glyphRegular0 = pkgs.fetchurl {
    url = "https://fonts.openmaptiles.org/Open%20Sans%20Regular/0-255.pbf";
    sha256 = "1znbpcg7ki2arknd2zmzr1xm2fiz74404jj3pfdzdmia9wldp2qc";
  };
  glyphRegular1 = pkgs.fetchurl {
    url = "https://fonts.openmaptiles.org/Open%20Sans%20Regular/256-511.pbf";
    sha256 = "12m6icbv66z85w6rhpw0i987hxlfspqxrix64srbxvb4s0wasqlr";
  };
  glyphSemibold0 = pkgs.fetchurl {
    url = "https://fonts.openmaptiles.org/Open%20Sans%20Semibold/0-255.pbf";
    sha256 = "0rc37r2pnsa2ywrhir91wgj24bvfsym2cgcs4hd3acbmw08p1nk4";
  };
  glyphSemibold1 = pkgs.fetchurl {
    url = "https://fonts.openmaptiles.org/Open%20Sans%20Semibold/256-511.pbf";
    sha256 = "19fpcsrjk6ss5wibzqdp209dqvv4pydvyrpyvz61ghcqh6yqnabq";
  };

  glyphs = pkgs.runCommand "openmaptiles-glyphs" { } ''
    mkdir -p "$out/Open Sans Regular" "$out/Open Sans Semibold"
    cp ${glyphRegular0} "$out/Open Sans Regular/0-255.pbf"
    cp ${glyphRegular1} "$out/Open Sans Regular/256-511.pbf"
    cp ${glyphSemibold0} "$out/Open Sans Semibold/0-255.pbf"
    cp ${glyphSemibold1} "$out/Open Sans Semibold/256-511.pbf"
  '';

  indexHtml = pkgs.writeText "offline-maps-index.html" ''
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Offline Illinois Map</title>
      <link rel="stylesheet" href="maplibre-gl.css">
      <style>
        html, body { margin: 0; padding: 0; height: 100%; }
        #map { position: absolute; inset: 0; }
        #hint {
          position: absolute; right: 12px; bottom: 12px; z-index: 1;
          background: rgba(255,255,255,.88); padding: 6px 10px;
          font: 12px sans-serif; border-radius: 4px;
        }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <div id="hint">Offline OpenStreetMap &middot; right-click for coordinates</div>
      <script src="pmtiles.js"></script>
      <script src="maplibre-gl.js"></script>
      <script>
        var protocol = new pmtiles.Protocol();
        maplibregl.addProtocol("pmtiles", protocol.tile);
        var map = new maplibregl.Map({
          container: "map",
          style: "style.json",
          center: [-89.0, 40.0],
          zoom: 6,
          minZoom: 5,
          maxBounds: [[-91.7, 36.8], [-87.3, 42.7]]
        });
        map.addControl(new maplibregl.NavigationControl(), "top-right");
        map.addControl(new maplibregl.ScaleControl({ maxWidth: 160, unit: "imperial" }), "bottom-left");
      </script>
    </body>
    </html>
  '';

  styleJson = pkgs.writeText "offline-maps-style.json" (
    builtins.toJSON {
      version = 8;
      name = "Offline Illinois";
      glyphs = "/maps/glyphs/{fontstack}/{range}.pbf";
      sources.osm = {
        type = "vector";
        url = "pmtiles:///maps/illinois.pmtiles";
        attribution = "&copy; <a href=\"https://www.openstreetmap.org/copyright\">OpenStreetMap</a> contributors, <a href=\"https://openmaptiles.org/\">OpenMapTiles</a>";
      };
      layers = [
        {
          id = "background";
          type = "background";
          paint.background-color = "#f2efe9";
        }
        {
          id = "landcover";
          type = "fill";
          source = "osm";
          source-layer = "landcover";
          paint = {
            fill-color = [
              "match"
              [
                "get"
                "class"
              ]
              "wood"
              "#cde3cd"
              "grass"
              "#dcefd6"
              "crops"
              "#e8e0b0"
              "#eae7df"
            ];
            fill-opacity = 0.85;
          };
        }
        {
          id = "park";
          type = "fill";
          source = "osm";
          source-layer = "park";
          paint.fill-color = "#cfead0";
        }
        {
          id = "water";
          type = "fill";
          source = "osm";
          source-layer = "water";
          filter = [
            "=="
            [ "geometry-type" ]
            "Polygon"
          ];
          paint.fill-color = "#a6cfe8";
        }
        {
          id = "waterway";
          type = "line";
          source = "osm";
          source-layer = "waterway";
          paint = {
            line-color = "#a6cfe8";
            line-width = [
              "interpolate"
              [ "linear" ]
              [ "zoom" ]
              8
              0.5
              14
              3
            ];
          };
        }
        {
          id = "boundary";
          type = "line";
          source = "osm";
          source-layer = "boundary";
          paint = {
            line-color = "#b0a9a0";
            line-dasharray = [
              2
              2
            ];
            line-width = 1;
          };
        }
        {
          id = "transportation-casing";
          type = "line";
          source = "osm";
          source-layer = "transportation";
          filter = [
            "in"
            [
              "get"
              "class"
            ]
            [
              "literal"
              [
                "motorway"
                "trunk"
                "primary"
                "secondary"
              ]
            ]
          ];
          layout = {
            line-cap = "round";
            line-join = "round";
          };
          paint.line-width = [
            "interpolate"
            [ "linear" ]
            [ "zoom" ]
            8
            0.5
            12
            2
            16
            8
          ];
        }
        {
          id = "transportation";
          type = "line";
          source = "osm";
          source-layer = "transportation";
          paint = {
            line-color = [
              "match"
              [
                "get"
                "class"
              ]
              "motorway"
              "#f2c78f"
              "trunk"
              "#f2c78f"
              "primary"
              "#f7d9a8"
              "secondary"
              "#fbe3bb"
              "tertiary"
              "#ffffff"
              "minor"
              "#ffffff"
              "service"
              "#ffffff"
              "path"
              "#d9c9a8"
              "#e8e8e8"
            ];
            line-width = [
              "interpolate"
              [ "linear" ]
              [ "zoom" ]
              8
              0.4
              12
              1.2
              16
              5
            ];
          };
        }
        {
          id = "building";
          type = "fill";
          source = "osm";
          source-layer = "building";
          minzoom = 13;
          paint = {
            fill-color = "#d8d2c8";
            fill-outline-color = "#c5beb2";
          };
        }
        {
          id = "place-label";
          type = "symbol";
          source = "osm";
          source-layer = "place";
          filter = [
            "has"
            "name"
          ];
          layout = {
            text-field = [
              "get"
              "name"
            ];
            text-font = [ "Open Sans Regular" ];
            text-size = [
              "interpolate"
              [ "linear" ]
              [ "zoom" ]
              6
              10
              10
              14
            ];
            text-anchor = "center";
          };
          paint = {
            text-color = "#333333";
            text-halo-color = "#ffffff";
            text-halo-width = 1;
          };
        }
        {
          id = "road-label";
          type = "symbol";
          source = "osm";
          source-layer = "transportation_name";
          filter = [
            "has"
            "name"
          ];
          layout = {
            symbol-placement = "line";
            text-field = [
              "get"
              "name"
            ];
            text-font = [ "Open Sans Regular" ];
            text-size = 11;
          };
          paint = {
            text-color = "#666666";
            text-halo-color = "#ffffff";
            text-halo-width = 1;
          };
        }
      ];
    }
  );

  viewer = pkgs.linkFarm "offline-map-viewer" [
    {
      name = "index.html";
      path = indexHtml;
    }
    {
      name = "style.json";
      path = styleJson;
    }
  ];

  planetiler = pkgs.writeShellScriptBin "planetiler" ''
    exec ${pkgs.jdk25}/bin/java -Xmx4g -jar ${planetilerJar} "$@"
  '';
in
{
  assertions = [
    {
      assertion = config.networking.hostName == "granite";
      message = "the offline map viewer is currently intended for the granite host";
    }
  ];

  environment.systemPackages = [ planetiler ];

  # The PMTiles file stays a manual download/conversion under /platter. The
  # viewer assets are symlinked from the Nix store into the same directory so
  # nginx serves everything from one location with no runtime internet access.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
    "L+ ${dataDir}/index.html - - - - ${viewer}/index.html"
    "L+ ${dataDir}/style.json - - - - ${viewer}/style.json"
    "L+ ${dataDir}/maplibre-gl.js - - - - ${maplibreJs}"
    "L+ ${dataDir}/maplibre-gl.css - - - - ${maplibreCss}"
    "L+ ${dataDir}/pmtiles.js - - - - ${pmtilesJs}"
    "L+ ${dataDir}/glyphs - - - - ${glyphs}"
  ];

  # The reference module owns the shared vhost, listener and firewall rule.
  services.nginx = {
    enable = true;
    virtualHosts."reference-internal" = {
      locations."/maps/" = {
        alias = "${dataDir}/";
        extraConfig = ''
          autoindex on;
          autoindex_exact_size off;
          add_header Accept-Ranges bytes;
        '';
      };
    };
  };
}
