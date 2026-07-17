{
  # Suricata IDS (SOC Phase 2). Alert-only — af-packet capture, no
  # inline/IPS mode. EVE JSON events are shipped to Loki on soc by an
  # extra Alloy config file (Alloy loads every *.alloy in /etc/alloy, so
  # this composes with the fleet-wide journal config from
  # services-observability, which this module assumes is present).
  nixos.modules.services-suricata =
    { config, lib, ... }:
    let
      cfg = config.thorn.suricata;
    in
    {
      options.thorn.suricata.interfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "eth0" ];
        description = ''
          Interfaces Suricata captures on via af-packet. Include "lo" on
          hosts whose real ingress is a tunnel terminating on loopback
          (e.g. cloudflared), since that's where the decrypted traffic is.
        '';
      };

      config = {
        services.suricata = {
          enable = true;
          settings = {
            vars.address-groups.HOME_NET = "[172.16.25.0/24,127.0.0.0/8]";
            af-packet = map (interface: { inherit interface; }) cfg.interfaces;

            # Locally-originated and loopback packets carry no valid
            # checksums (offloading), which would otherwise make the
            # stream engine drop everything as invalid.
            stream.checksum-validation = "no";

            outputs = [
              {
                eve-log = {
                  enabled = true;
                  filetype = "regular";
                  filename = "eve.json";
                  community-id = true;
                  types = [
                    { alert.tagged-packets = "yes"; }
                    { anomaly.enabled = "yes"; }
                    { ssh = { }; }
                  ];
                };
              }
            ];
          };
        };

        # The default enabledSources list pulls ~10 rulesets; ET Open plus
        # the abuse.ch lists cover this LAN fine and keep memory in check.
        services.suricata.enabledSources = [
          "et/open"
          "abuse.ch/sslbl-blacklist"
          "abuse.ch/sslbl-c2"
          "oisf/trafficid"
        ];

        # Drop ET Open's modbus/dnp3 industrial-protocol rules. Suricata
        # 8.0.3 can't enable dnp3 detection at all, so those rules fail to
        # parse, and the strict startup test (-T) treats any unparseable
        # rule as fatal — crash-looping the service. suricata-update's
        # `re:` disables every rule matching the pattern; neither protocol
        # is relevant on a web host. (Overrides the module's default, which
        # only disables five dnp3 SIDs.)
        services.suricata.disabledRules = [
          "re:modbus"
          "re:dnp3"
        ];

        # Ship EVE events to Loki. Alloy runs with DynamicUser; group
        # access is what lets it read Suricata's log directory.
        systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "suricata" ];
        environment.etc."alloy/suricata.alloy".text = ''
          loki.source.file "suricata" {
            targets = [{
              "__path__" = "/var/log/suricata/eve.json",
              "job"      = "suricata",
              "host"     = "${config.networking.hostName}",
            }]
            forward_to = [loki.write.soc.receiver]
          }
        '';
      };
    };
}
