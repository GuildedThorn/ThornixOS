{
  # Suricata IDS (SOC Phase 2). Alert-only — af-packet capture, no
  # inline/IPS mode. EVE JSON events are shipped to Loki on soc by an
  # extra Alloy config file (Alloy loads every *.alloy in /etc/alloy, so
  # this composes with the fleet-wide journal config from
  # services-observability, which this module assumes is present).
  nixos.modules.services-suricata =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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

      options.thorn.suricata.bpfFilter = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "ip or ip6 or arp";
        description = ''
          Optional BPF capture filter applied to every af-packet interface.
          Scopes the sensor to the traffic it exists to inspect — e.g. a web
          host's IDS has no business decoding the switch's STP/LLDP chatter,
          which otherwise reaches the VM bridge and trips L2 decoder events.
          This is scoping, not alert suppression: filtered frames are never
          captured, which also saves CPU.
        '';
      };

      config = {
        services.suricata = {
          enable = true;
          settings = {
            vars.address-groups.HOME_NET = "[172.16.25.0/24,127.0.0.0/8]";
            af-packet = map (
              interface:
              { inherit interface; } // lib.optionalAttrs (cfg.bpfFilter != null) { bpf-filter = cfg.bpfFilter; }
            ) cfg.interfaces;

            # Locally-originated and loopback packets carry no valid
            # checksums (offloading), which would otherwise make the
            # stream engine drop everything as invalid.
            stream.checksum-validation = "no";

            # Loopback's MTU is 64KB and the default capture size is ~1514,
            # so every large lo packet arrived truncated — the engine was
            # silently payload-blind on exactly the interface carrying the
            # decrypted HTTP (surfaced as an IPv4/AF-PACKET truncated-packet
            # alert storm the moment fresh decoder rules went live). Size the
            # capture to fit the whole packet instead of suppressing the
            # rules that reported it.
            default-packet-size = 65549;

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

        # Rules to strip from the built ruleset (suricata-update comments
        # them out). Overrides the module default (five dnp3 SIDs).
        services.suricata.disabledRules = [
          # SURICATA Ethertype unknown — a layer-2 decoder event that fires
          # on every non-IP frame on the wire (STP/BPDU, LLDP from switches).
          # Benign, no src/dst IP, and ~99% of this sensor's alert volume.
          "2200121"
          # ET Open's modbus/dnp3 industrial-protocol rules: irrelevant on a
          # web host, and Suricata 8.0.3 can't enable dnp3 detection at all,
          # so those rules fail to parse and the strict -T test aborts the
          # whole load (crash-looping the service). `re:` matches by pattern.
          "re:modbus"
          "re:dnp3"
          # ET INFO DNS Query to Cloudflare Tunneling Domain (argotunnel).
          # The rule detects attacker-run Cloudflare tunnels — but this
          # host's ingress IS a legitimate cloudflared tunnel, so it fires
          # on our own housekeeping forever and can never distinguish. If a
          # span-port LAN sensor is ever added, keep the rule enabled there:
          # that's where a surprise argotunnel lookup means something.
          "2047122"
          # ET INFO Commonly Abused Github-like Site (codeberg.org in DNS).
          # The flake pulls the awww input from Codeberg, so every comin
          # deploy on this host resolves it.
          "2035173"
        ];

        # The pinned nixpkgs Suricata module currently emits
        # `ProtectProc=true`, which is not a valid systemd mode and is
        # therefore ignored. Preserve the intended process isolation with a
        # supported value until the upstream module is corrected.
        systemd.services.suricata.serviceConfig.ProtectProc = lib.mkForce "invisible";

        # Disable NIC offloads on the physical capture interfaces so the
        # engine sees real wire-sized segments: GRO/GSO hand af-packet
        # kernel-merged super-frames, which distort stream reassembly and
        # overflow any fixed capture size. "lo" is skipped — loopback
        # packets are genuinely 64KB (that's what default-packet-size is
        # for), and there is no wire to be faithful to.
        systemd.services.suricata-nic-offload = {
          description = "Disable NIC offloads on Suricata capture interfaces";
          wantedBy = [ "suricata.service" ];
          before = [ "suricata.service" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = lib.concatMapStringsSep "\n" (
            interface:
            lib.concatMapStringsSep "\n"
              (feature: "${pkgs.ethtool}/bin/ethtool -K ${interface} ${feature} off || true")
              [
                "gro"
                "gso"
                "tso"
                "lro"
              ]
          ) (lib.filter (i: i != "lo") cfg.interfaces);
        };

        # Suricata only reads rules at startup, and the nixpkgs module never
        # tells it otherwise — so the daily suricata-update timer rewrote
        # rules on disk while the engine kept detecting with whatever was in
        # memory at its last restart (observed weeks stale: disabledRules
        # ignored, rule thresholds missing, and — the part that matters —
        # new ET Open signatures never reaching the engine). SIGUSR2 is
        # Suricata's live ruleset-reload. "+" runs it outside the update
        # unit's DynamicUser sandbox; "-" tolerates the sensor not running
        # yet (at boot the update completes before suricata starts).
        systemd.services.suricata-update.serviceConfig.ExecStartPost =
          "-+/run/current-system/sw/bin/systemctl kill --signal=SIGUSR2 suricata.service";

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
