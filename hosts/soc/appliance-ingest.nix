{ ... }:
{
  # Syslog → Loki ingest for non-NixOS devices (pfSense today; any
  # appliance that can't run Alloy). pfSense's FreeBSD syslogd emits
  # a non-standard RFC3164 with NO hostname field
  # (`<pri>TIMESTAMP tag: msg`), which Alloy's strict syslog parser
  # rejects outright. So rsyslog fronts it: it tolerantly accepts the
  # datagrams on 5514/udp, fills the missing hostname from the source
  # IP, and writes one file per source under /var/log/remote; Alloy
  # then tails those into Loki via the same loki.write.soc receiver.
  # Files are 0644 so Alloy's DynamicUser can read them. When the
  # firewall becomes a NixOS host it ships via journal instead and
  # this stays for other appliances. hosts/soc/networking.nix admits
  # this port only from explicitly listed appliance addresses.
  services.rsyslogd = {
    enable = true;
    # Avoid duplicating all local journal and appliance events in
    # /var/log/messages; Loki is the durable searchable store.
    defaultConfig = "";
    extraConfig = ''
      module(load="imudp")
      module(load="imtcp")
      input(type="imudp" port="5514")
      input(type="imtcp" port="5514")
      template(name="remotefile" type="string"
               string="/var/log/remote/%FROMHOST-IP%.log")
      if ($fromhost-ip != "127.0.0.1") then {
        action(type="omfile" dynaFile="remotefile"
               fileCreateMode="0644" dirCreateMode="0755")
        stop
      }
    '';
  };

  services.journald.extraConfig = ''
    SystemMaxUse=2G
    SystemKeepFree=5G
    MaxRetentionSec=7day
  '';

  # DNS query/reply logging is intentionally detailed and can be
  # substantially busier than the earlier IDS-only feed. Loki is the
  # durable searchable copy; keep one week of compressed raw files as
  # a short local recovery buffer instead of allowing the rsyslog
  # spool to grow without bound. HUP makes rsyslog reopen each file
  # after logrotate renames it.
  services.logrotate.settings."remote-appliance-syslog" = {
    files = "/var/log/remote/*.log";
    frequency = "daily";
    rotate = 7;
    compress = true;
    delaycompress = true;
    dateext = true;
    missingok = true;
    notifempty = true;
    create = "0644 root root";
    postrotate = "systemctl kill --signal=HUP syslog.service >/dev/null 2>&1 || true";
  };

  environment.etc."alloy/syslog.alloy".text = ''
    // Keep bounded appliance identities as labels while rsyslog
    // writes one file per source address.
    local.file_match "remote_syslog" {
      path_targets = [
        {
          "__path__" = "/var/log/remote/172.16.25.1.log",
          job        = "syslog",
          host       = "pfsense",
        },
        {
          "__path__" = "/var/log/remote/192.168.1.31.log",
          job        = "syslog",
          host       = "pineapple",
        },
      ]
    }

    loki.source.file "remote_syslog" {
      targets    = local.file_match.remote_syslog.targets
      forward_to = [loki.process.remote_syslog.receiver]
    }

    loki.process "remote_syslog" {
      // Use the event time preserved by rsyslog. If parsing ever
      // fails, keep the entry and fall back to its file-read time.
      stage.regex {
        expression = "^(?P<pfsense_event_ts>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+(?:\\.[0-9]+)?[+-][0-9]{2}:[0-9]{2})"
      }

      stage.timestamp {
        source            = "pfsense_event_ts"
        format            = "RFC3339Nano"
        action_on_failure = "skip"
      }

      // Unbound query records:
      //   query: CLIENT QNAME QTYPE QCLASS
      // Client addresses, names, and qtypes are metadata. Although
      // qtype is protocol-defined, its 16-bit space is large enough
      // for a compromised client to churn Loki streams. Only the
      // fixed event kind becomes a label.
      stage.match {
        // Anchor on the end of Unbound's thread prefix so internal
        // verbosity-3 messages such as `info: sending query:` do not
        // inflate the client-query counters when their regex fails.
        selector      = "{job=\"syslog\"} |= \" unbound[\" |= \"] query: \""
        pipeline_name = "pfsense_unbound_query"

        stage.regex {
          expression = "unbound\\[[0-9]+\\]: \\[[^]]+\\] query: (?P<dns_client_ip>\\S+) (?P<dns_qname>\\S+) (?P<dns_qtype_value>[A-Z0-9-]+) (?P<dns_qclass>\\S+)$"
        }

        stage.static_labels {
          values = {
            pfsense_log = "dns",
            dns_event   = "query",
          }
        }

        stage.structured_metadata {
          values = {
            dns_client_ip = "",
            dns_qname     = "",
            dns_qtype     = "dns_qtype_value",
            dns_qclass    = "",
          }
        }
      }

      // Unbound reply records append rcode, resolution seconds,
      // cache status (0/1), and response bytes to the query fields.
      stage.match {
        selector      = "{job=\"syslog\"} |= \" unbound[\" |= \"] reply: \""
        pipeline_name = "pfsense_unbound_reply"

        stage.regex {
          expression = "unbound\\[[0-9]+\\]: \\[[^]]+\\] reply: (?P<dns_client_ip>\\S+) (?P<dns_qname>\\S+) (?P<dns_qtype_value>[A-Z0-9-]+) (?P<dns_qclass>\\S+) (?P<dns_rcode_value>[A-Z0-9-]+) (?P<dns_response_seconds>[0-9.]+) (?P<dns_cached_value>[01]) (?P<dns_response_bytes>[0-9]+)$"
        }

        stage.static_labels {
          values = {
            pfsense_log = "dns",
            dns_event   = "reply",
          }
        }

        stage.labels {
          values = {
            dns_rcode  = "dns_rcode_value",
            dns_cached = "dns_cached_value",
          }
        }

        stage.structured_metadata {
          values = {
            dns_client_ip       = "",
            dns_qname           = "",
            dns_qtype           = "dns_qtype_value",
            dns_qclass          = "",
            dns_response_seconds = "",
            dns_response_bytes   = "",
          }
        }
      }

      // pfSense filterlog is a documented CSV-like format. Parse
      // the common prefix once; these labels all have bounded local
      // or protocol-defined value sets. Rule identifiers, addresses,
      // ports, lengths, and header details remain metadata.
      stage.match {
        selector      = "{job=\"syslog\"} |= \" filterlog[\""
        pipeline_name = "pfsense_filterlog"

        stage.regex {
          expression = "filterlog\\[[0-9]+\\]: (?P<firewall_rule>[^,]*),(?P<firewall_subrule>[^,]*),(?P<firewall_anchor>[^,]*),(?P<firewall_tracker>[^,]*),(?P<firewall_interface_value>[^,]*),(?P<firewall_reason>[^,]*),(?P<firewall_action_value>[^,]*),(?P<firewall_direction_value>[^,]*),(?P<firewall_ip_version_value>[46]),(?P<firewall_ip_payload>.*)$"
        }

        stage.static_labels {
          values = { pfsense_log = "firewall" }
        }

        stage.labels {
          values = {
            firewall_interface  = "firewall_interface_value",
            firewall_action     = "firewall_action_value",
            firewall_direction  = "firewall_direction_value",
            firewall_ip_version = "firewall_ip_version_value",
          }
        }

        stage.structured_metadata {
          values = {
            firewall_rule    = "",
            firewall_subrule = "",
            firewall_anchor  = "",
            firewall_tracker = "",
            firewall_reason  = "",
          }
        }

        // IPv4 payload: TOS, ECN, TTL, ID, fragment offset/flags,
        // protocol, packet length, source, destination, then the
        // protocol-specific tail.
        stage.match {
          selector      = "{pfsense_log=\"firewall\", firewall_ip_version=\"4\"}"
          pipeline_name = "pfsense_filterlog_ipv4"

          stage.regex {
            source     = "firewall_ip_payload"
            expression = "(?P<firewall_tos>[^,]*),(?P<firewall_ecn>[^,]*),(?P<firewall_ttl>[^,]*),(?P<firewall_ip_id>[^,]*),(?P<firewall_fragment_offset>[^,]*),(?P<firewall_ip_flags>[^,]*),(?P<firewall_protocol_id>[^,]*),(?P<firewall_protocol_value>[^,]*),(?P<firewall_packet_length>[^,]*),(?P<geoip_src_ip>[^,]*),(?P<firewall_destination_ip>[^,]*)(?:,(?P<firewall_transport_payload>.*))?$"
          }

          stage.template {
            source   = "firewall_protocol_value"
            template = "{{ ToLower .Value }}"
          }

          stage.labels {
            values = { firewall_protocol = "firewall_protocol_value" }
          }

          stage.structured_metadata {
            values = {
              firewall_tos             = "",
              firewall_ecn             = "",
              firewall_ttl             = "",
              firewall_ip_id           = "",
              firewall_fragment_offset = "",
              firewall_ip_flags        = "",
              firewall_protocol_id     = "",
              firewall_packet_length   = "",
              firewall_source_ip       = "geoip_src_ip",
              firewall_destination_ip  = "",
            }
          }

          // ix0 is this firewall's WAN. Only blocked packets entering
          // there represent hostile external sources; enriching LAN
          // traffic would turn the threat map into ordinary usage.
          stage.match {
            selector      = "{pfsense_log=\"firewall\", firewall_interface=\"ix0\", firewall_action=\"block\", firewall_direction=\"in\"}"
            pipeline_name = "geoip_pfsense_wan_block_source"

            stage.geoip {
              source  = "geoip_src_ip"
              db      = "/etc/GeoIP/DBIP-City-Lite.mmdb"
              db_type = "city"
            }

            stage.geoip {
              source  = "geoip_src_ip"
              db      = "/etc/GeoIP/DBIP-ASN-Lite.mmdb"
              db_type = "asn"
            }

            stage.static_labels {
              values = { geoip_enriched = "true" }
            }

            stage.structured_metadata {
              values = {
                geoip_src_ip                         = "",
                geoip_city_name                      = "",
                geoip_country_name                   = "",
                geoip_country_code                   = "",
                geoip_continent_code                 = "",
                geoip_location_latitude              = "",
                geoip_location_longitude             = "",
                geoip_timezone                       = "",
                geoip_autonomous_system_number       = "",
                geoip_autonomous_system_organization = "",
              }
            }
          }
        }

        // IPv6 replaces the IPv4 header fields with traffic class,
        // flow label, and hop limit. Normalize its observed uppercase
        // protocol text before making the bounded protocol label.
        stage.match {
          selector      = "{pfsense_log=\"firewall\", firewall_ip_version=\"6\"}"
          pipeline_name = "pfsense_filterlog_ipv6"

          stage.regex {
            source     = "firewall_ip_payload"
            expression = "(?P<firewall_traffic_class>[^,]*),(?P<firewall_flow_label>[^,]*),(?P<firewall_hop_limit>[^,]*),(?P<firewall_protocol_value>[^,]*),(?P<firewall_protocol_id>[^,]*),(?P<firewall_packet_length>[^,]*),(?P<geoip_src_ip>[^,]*),(?P<firewall_destination_ip>[^,]*)(?:,(?P<firewall_transport_payload>.*))?$"
          }

          stage.template {
            source   = "firewall_protocol_value"
            template = "{{ ToLower .Value }}"
          }

          stage.labels {
            values = { firewall_protocol = "firewall_protocol_value" }
          }

          stage.structured_metadata {
            values = {
              firewall_traffic_class = "",
              firewall_flow_label    = "",
              firewall_hop_limit     = "",
              firewall_protocol_id   = "",
              firewall_packet_length = "",
              firewall_source_ip     = "geoip_src_ip",
              firewall_destination_ip = "",
            }
          }
        }

        // TCP and UDP share the first three transport fields. TCP's
        // remaining details are parsed separately below.
        stage.match {
          selector      = "{pfsense_log=\"firewall\", firewall_protocol=~\"tcp|udp\"}"
          pipeline_name = "pfsense_filterlog_transport"

          stage.regex {
            source     = "firewall_transport_payload"
            expression = "(?P<firewall_source_port>[^,]*),(?P<firewall_destination_port>[^,]*),(?P<firewall_data_length>[^,]*)(?:,(?P<firewall_tcp_payload>.*))?$"
          }

          stage.structured_metadata {
            values = {
              firewall_source_port      = "",
              firewall_destination_port = "",
              firewall_data_length      = "",
            }
          }

          stage.match {
            selector      = "{pfsense_log=\"firewall\", firewall_protocol=\"tcp\"}"
            pipeline_name = "pfsense_filterlog_tcp"

            stage.regex {
              source     = "firewall_tcp_payload"
              expression = "(?P<firewall_tcp_flags>[^,]*),(?P<firewall_tcp_sequence>[^,]*),(?P<firewall_tcp_ack>[^,]*),(?P<firewall_tcp_window>[^,]*),(?P<firewall_tcp_urg>[^,]*),(?P<firewall_tcp_options>.*)$"
            }

            stage.structured_metadata {
              values = {
                firewall_tcp_flags    = "",
                firewall_tcp_sequence = "",
                firewall_tcp_ack      = "",
                firewall_tcp_window   = "",
                firewall_tcp_urg      = "",
                firewall_tcp_options  = "",
              }
            }
          }
        }
      }

      // Give every pfSense Suricata entry a bounded source-type
      // label, while leaving low-priority diagnostics searchable.
      stage.match {
        selector      = "{job=\"syslog\"} |= \" suricata\" |= \"[Priority: \""
        pipeline_name = "pfsense_suricata"

        stage.static_labels {
          values = { pfsense_log = "suricata" }
        }
      }

      // Only Suricata priorities 1/2 enter the hostile-source map.
      stage.match {
        selector      = "{job=\"syslog\"} |= \"suricata\" |~ \"Priority: [12]\""
        pipeline_name = "geoip_pfsense_ids_source"

        stage.regex {
          expression = "\\{[A-Z0-9]+\\}\\s+(?P<geoip_src_ip>(?:[0-9]{1,3}\\.){3}[0-9]{1,3})(?::[0-9]+)?\\s+->"
        }

        stage.geoip {
          source  = "geoip_src_ip"
          db      = "/etc/GeoIP/DBIP-City-Lite.mmdb"
          db_type = "city"
        }

        stage.geoip {
          source  = "geoip_src_ip"
          db      = "/etc/GeoIP/DBIP-ASN-Lite.mmdb"
          db_type = "asn"
        }

        // A single constant stream label lets dashboards select only
        // enriched findings without indexing any dynamic GeoIP data.
        stage.static_labels {
          values = { geoip_enriched = "true" }
        }

        stage.structured_metadata {
          values = {
            geoip_src_ip                         = "",
            geoip_city_name                      = "",
            geoip_country_name                   = "",
            geoip_country_code                   = "",
            geoip_continent_code                 = "",
            geoip_location_latitude              = "",
            geoip_location_longitude             = "",
            geoip_timezone                       = "",
            geoip_autonomous_system_number       = "",
            geoip_autonomous_system_organization = "",
          }
        }
      }

      forward_to = [loki.write.soc.receiver]
    }
  '';
}
