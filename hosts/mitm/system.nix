{ inputs, ... }:
let
  adminSshKeys = import ../../hosts/mitm/admin-ssh-keys.nix;
  deckHost = "172.16.25.26";
  workflowModelHost = "192.168.1.6";
  workflowModelName = "qwen3:14b";
  workflowModelUrl = "http://${workflowModelHost}:11435";
  serviceCatalog = import ../../hosts/service-catalog.nix;
  serviceEntitySlug = service: builtins.replaceStrings [ "-" ] [ "_" ] service.id;
  serviceEntityId = service: "sensor.thornix_service_${serviceEntitySlug service}";
  serviceEntityIds = map serviceEntityId serviceCatalog;
  serviceCatalogMatch = service: ''
    {% set service_data = state_attr("sensor.thornix_soc_status", "services") or {} %}
    {% set service_catalog = service_data.get("catalog", []) %}
    {% set service_matches = service_catalog | selectattr("id", "equalto", "${service.id}") | list %}
  '';
  serviceCatalogAttribute = service: attribute: ''
    ${serviceCatalogMatch service}
    {{ service_matches[0].get("${attribute}") if service_matches | count > 0 else none }}
  '';
  mkServiceSensor = service: {
    name = "Thornix Service ${service.name}";
    default_entity_id = serviceEntityId service;
    unique_id = "thornix_service_${serviceEntitySlug service}";
    icon = service.icon;
    availability = ''
      {{ states("sensor.thornix_soc_status") not in ["unknown", "unavailable"] }}
    '';
    state = ''
      ${serviceCatalogMatch service}
      {{ service_matches[0].get("status", "unavailable") if service_matches | count > 0 else "not_monitored" }}
    '';
    attributes = {
      service_id = service.id;
      service_name = service.name;
      role = service.role;
      host = service.host;
      aliases = builtins.concatStringsSep ", " service.aliases;
      probe_url = service.probeUrl;
      launch_url = service.launchUrl;
      monitored = ''
        ${serviceCatalogMatch service}
        {{ service_matches | count > 0 }}
      '';
      latency_seconds = serviceCatalogAttribute service "latency_seconds";
      availability_percent = serviceCatalogAttribute service "availability_percent";
      latency_p95_seconds = serviceCatalogAttribute service "latency_p95_seconds";
      slo_status = serviceCatalogAttribute service "slo_status";
      http_status = serviceCatalogAttribute service "http_status";
      tls_days_remaining = serviceCatalogAttribute service "tls_days_remaining";
      reliability_window = ''
        {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("window", "24h") }}
      '';
      observed_at = ''{{ state_attr("sensor.thornix_soc_status", "generated_at") }}'';
    };
  };
in
{
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.home-assistant = {
    enable = true;
    openFirewall = false;
    openFirewallForComponents = true;
    extraComponents = [
      "analytics"
      "bluetooth"
      "co2signal"
      "cloud"
      "default_config"
      "esphome"
      "google_translate"
      "govee_ble"
      "group"
      "isal"
      "jellyfin"
      "met"
      "ollama"
      "radio_browser"
      "rest"
      "rest_command"
      "shopping_list"
      "ssdp"
      "template"
      "wyoming"
      "zeroconf"
    ];
    config = {
      default_config = { };
      homeassistant.internal_url = "https://mitm.guildedthorn.arpa";
      frontend.themes.Thorn = {
        "accent-color" = "#68aee8";
        "app-header-background-color" = "#0d1117";
        "app-header-text-color" = "#e6edf3";
        "card-background-color" = "#151d27";
        "divider-color" = "rgba(151, 166, 181, 0.16)";
        "ha-card-border-radius" = "18px";
        "ha-card-border-width" = "0px";
        "ha-card-box-shadow" = "0 8px 28px rgba(0, 0, 0, 0.28)";
        "primary-background-color" = "#0d1117";
        "primary-color" = "#d8a657";
        "primary-text-color" = "#e6edf3";
        "secondary-background-color" = "#111821";
        "secondary-text-color" = "#9ca9b7";
      };
      http = {
        server_host = "127.0.0.1";
        trusted_proxies = [ "127.0.0.1" ];
        use_x_forwarded_for = true;
      };
      lovelace.dashboards."thorn-home" = {
        mode = "yaml";
        filename = "thorn-home.yaml";
        title = "Thorn Home";
        icon = "mdi:shield-home-outline";
        show_in_sidebar = true;
      };
      input_boolean.deck_voice_local_fallback = {
        name = "Deck Voice local model fallback";
        icon = "mdi:robot-off-outline";
        initial = false;
      };
      group.thornix_services = {
        name = "ThornixOS Services";
        icon = "mdi:server-network";
        entities = serviceEntityIds;
      };
      template = [
        {
          sensor = [
            {
              name = "Thornix Service Health";
              default_entity_id = "sensor.thornix_service_health";
              unique_id = "thornix_service_health";
              icon = "mdi:server-network";
              availability = ''
                {{ states("sensor.thornix_soc_status") not in ["unknown", "unavailable"] }}
              '';
              state = ''
                {% set services = state_attr("sensor.thornix_soc_status", "services") or {} %}
                {% set checked = services.get("checked", 0) | int(0) %}
                {% set healthy = services.get("healthy", 0) | int(0) %}
                {{ "healthy" if checked > 0 and healthy == checked else "degraded" if checked > 0 else "unavailable" }}
              '';
              attributes = {
                checked = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("checked", 0) }}
                '';
                healthy = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("healthy", 0) }}
                '';
                unavailable = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("unavailable", []) }}
                '';
                slow = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("slow", []) }}
                '';
                slo_met = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("slo_met", 0) }}
                '';
                slo_attention = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("slo_attention", []) }}
                '';
                slowest = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("slowest", []) }}
                '';
                reliability_window = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("window", "24h") }}
                '';
                catalog_size = "${toString (builtins.length serviceCatalog)}";
              };
            }
            {
              name = "Thornix Service Reliability";
              default_entity_id = "sensor.thornix_service_reliability";
              unique_id = "thornix_service_reliability";
              icon = "mdi:chart-timeline-variant-shimmer";
              availability = ''
                {{ states("sensor.thornix_soc_status") not in ["unknown", "unavailable"] }}
              '';
              state = ''
                {% set services = state_attr("sensor.thornix_soc_status", "services") or {} %}
                {% set checked = services.get("checked", 0) | int(0) %}
                {% set attention = services.get("slo_attention", []) %}
                {% set counts = namespace(breached=0) %}
                {% for item in attention %}
                  {% if item.get("status") in ["down", "breached"] %}
                    {% set counts.breached = counts.breached + 1 %}
                  {% endif %}
                {% endfor %}
                {{ "unavailable" if checked == 0 else "breached" if counts.breached > 0 else "at_risk" if attention | count > 0 else "healthy" }}
              '';
              attributes = {
                checked = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("checked", 0) }}
                '';
                slo_met = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("slo_met", 0) }}
                '';
                attention = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("slo_attention", []) }}
                '';
                target = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("slo_target", {}) }}
                '';
                window = ''
                  {{ (state_attr("sensor.thornix_soc_status", "services") or {}).get("window", "24h") }}
                '';
              };
            }
          ]
          ++ map mkServiceSensor serviceCatalog;
        }
      ];
      rest = [
        {
          resource = "https://soc.guildedthorn.arpa:9443/api/v1/ops-summary";
          method = "POST";
          payload = ''{"window":"24h"}'';
          headers."Content-Type" = "application/json";
          scan_interval = 60;
          timeout = 30;
          sensor = [
            {
              name = "Thornix SOC Status";
              unique_id = "thornix_soc_status";
              value_template = ''{{ value_json.summary.status | default("unavailable") }}'';
              json_attributes = [
                "generated_at"
                "window"
                "summary"
                "actions"
                "fleet"
                "services"
                "maintenance"
                "deployment"
                "security"
                "errors"
              ];
            }
          ];
        }
        {
          resource = "http://${deckHost}:10701/api/health";
          method = "GET";
          scan_interval = 15;
          timeout = 5;
          sensor = [
            {
              name = "Deck Voice Health";
              unique_id = "deck_voice_health";
              value_template = ''{{ value_json.status | default("unavailable") }}'';
              json_attributes = [
                "connected"
                "streaming"
                "voice_state"
                "last_event"
                "last_event_age"
                "uptime_seconds"
                "recovery_count"
                "last_recovery"
                "recovery_reason"
                "audio"
              ];
            }
          ];
        }
        {
          resource = "http://${deckHost}:11434/api/tags";
          method = "GET";
          scan_interval = 15;
          timeout = 5;
          sensor = [
            {
              name = "Deck Conversation Model";
              unique_id = "deck_conversation_model";
              value_template = ''
                {% set models = value_json.models | default([], true) %}
                {{ "ready" if models | selectattr("name", "equalto", "granite4.1:3b") | list | count > 0 else "missing" }}
              '';
            }
          ];
        }
        {
          resource = "${workflowModelUrl}/api/tags";
          method = "GET";
          scan_interval = 30;
          timeout = 5;
          sensor = [
            {
              name = "Casita Workflow Model";
              unique_id = "casita_workflow_model";
              value_template = ''
                {% set models = value_json.models | default([], true) %}
                {{ "ready" if models | selectattr("name", "equalto", "${workflowModelName}") | list | count > 0 else "missing" }}
              '';
            }
          ];
        }
        {
          resource = "http://${deckHost}:10202/health";
          method = "GET";
          scan_interval = 15;
          timeout = 5;
          sensor = [
            {
              name = "Deck Natural Voice";
              unique_id = "deck_natural_voice";
              value_template = ''{{ value_json.status | default("unavailable") }}'';
              json_attributes = [
                "engine"
                "voice"
                "sample_rate"
                "uptime_seconds"
                "synthesis_count"
                "natural_count"
                "fast_count"
                "fallback_count"
                "last_synthesis_seconds"
                "last_mode"
                "last_error"
              ];
            }
          ];
        }
      ];
      rest_command.deck_voice_visual_update = {
        url = "http://${deckHost}:10701/api/home";
        method = "post";
        content_type = "application/json";
        payload = ''
          {% set service_namespace = namespace(items=[]) %}
          {% for service in expand("group.thornix_services") %}
            {% set service_namespace.items = service_namespace.items + [{
              "id": state_attr(service.entity_id, "service_id") or service.entity_id,
              "name": state_attr(service.entity_id, "service_name") or service.name,
              "role": state_attr(service.entity_id, "role") or "ThornixOS service",
              "host": state_attr(service.entity_id, "host") or "",
              "aliases": state_attr(service.entity_id, "aliases") or "",
              "status": service.state,
              "monitored": state_attr(service.entity_id, "monitored") | default(false, true),
              "latency_seconds": state_attr(service.entity_id, "latency_seconds"),
              "availability_percent": state_attr(service.entity_id, "availability_percent"),
              "latency_p95_seconds": state_attr(service.entity_id, "latency_p95_seconds"),
              "slo_status": state_attr(service.entity_id, "slo_status") or "unknown",
              "reliability_window": state_attr(service.entity_id, "reliability_window") or "24h",
              "observed_at": state_attr(service.entity_id, "observed_at"),
              "http_status": state_attr(service.entity_id, "http_status"),
              "tls_days_remaining": state_attr(service.entity_id, "tls_days_remaining"),
              "url": state_attr(service.entity_id, "launch_url") or ""
            }] %}
          {% endfor %}
          {{ {
            "sent_at": as_timestamp(now()),
            "weather": {
              "condition": states("weather.forecast_home"),
              "temperature": state_attr("weather.forecast_home", "temperature"),
              "temperature_unit": state_attr("weather.forecast_home", "temperature_unit"),
              "humidity": state_attr("weather.forecast_home", "humidity"),
              "forecast": forecast | default([], true)
            },
            "person": {
              "name": "Jamie",
              "state": states("person.jamie_duddleston")
            },
            "rack": {
              "temperature": states("sensor.h5179_f81a_temperature"),
              "temperature_unit": state_attr("sensor.h5179_f81a_temperature", "unit_of_measurement"),
              "humidity": states("sensor.h5179_f81a_humidity"),
              "battery": states("sensor.h5179_f81a_battery")
            },
            "backup": {
              "state": states("sensor.backup_backup_manager_state"),
              "last_attempted": states("sensor.backup_last_attempted_automatic_backup"),
              "last_successful": states("sensor.backup_last_successful_automatic_backup"),
              "next_scheduled": states("sensor.backup_next_scheduled_automatic_backup")
            },
            "voice": {
              "status": states("sensor.deck_voice_health"),
              "connected": state_attr("sensor.deck_voice_health", "connected"),
              "streaming": state_attr("sensor.deck_voice_health", "streaming"),
              "voice_state": state_attr("sensor.deck_voice_health", "voice_state"),
              "recovery_count": state_attr("sensor.deck_voice_health", "recovery_count"),
              "last_recovery": state_attr("sensor.deck_voice_health", "last_recovery"),
              "recovery_reason": state_attr("sensor.deck_voice_health", "recovery_reason") or "",
              "audio": state_attr("sensor.deck_voice_health", "audio") or {},
              "auto_gain": states("number.deck_voice_mic_auto_gain"),
              "mic_volume": states("number.deck_voice_mic_volume"),
              "noise_suppression": states("select.deck_voice_mic_noise_suppression"),
              "finished_speaking": states("select.deck_voice_finished_speaking_detection"),
              "wake_word": states("select.deck_voice_wake_word"),
              "assistant": states("select.deck_voice_assistant"),
              "model": states("sensor.deck_conversation_model"),
              "model_name": "granite4.1:3b",
              "workflow_model": states("sensor.casita_workflow_model"),
              "workflow_model_name": "${workflowModelName}",
              "workflow_model_host": "nixos-gpu",
              "natural_voice": states("sensor.deck_natural_voice"),
              "natural_voice_name": state_attr("sensor.deck_natural_voice", "voice") or "af_heart",
              "voice_mode": state_attr("sensor.deck_natural_voice", "last_mode") or "natural",
              "voice_latency": state_attr("sensor.deck_natural_voice", "last_synthesis_seconds"),
              "muted": is_state("switch.deck_voice_mute", "on")
            },
            "sun": {
              "next_rising": states("sensor.sun_next_rising"),
              "next_setting": states("sensor.sun_next_setting")
            },
            "streams": {
              "count": states("sensor.thornflix_active_clients") | int(0)
            },
            "thornix_services": service_namespace.items,
            "media": [
              {
                "name": "Chrome",
                "state": states("media_player.chrome"),
                "title": state_attr("media_player.chrome", "media_title") or "",
                "artist": state_attr("media_player.chrome", "media_artist") or ""
              },
              {
                "name": "Chrome 2",
                "state": states("media_player.chrome_2"),
                "title": state_attr("media_player.chrome_2", "media_title") or "",
                "artist": state_attr("media_player.chrome_2", "media_artist") or ""
              },
              {
                "name": "Firefox",
                "state": states("media_player.firefox"),
                "title": state_attr("media_player.firefox", "media_title") or "",
                "artist": state_attr("media_player.firefox", "media_artist") or ""
              },
              {
                "name": "LG Smart TV",
                "state": states("media_player.lg_smart_tv"),
                "title": state_attr("media_player.lg_smart_tv", "media_title") or "",
                "artist": state_attr("media_player.lg_smart_tv", "media_artist") or ""
              },
              {
                "name": "Safari iPad",
                "state": states("media_player.safari_ipad"),
                "title": state_attr("media_player.safari_ipad", "media_title") or "",
                "artist": state_attr("media_player.safari_ipad", "media_artist") or ""
              }
            ],
            "soc": {
              "status": states("sensor.thornix_soc_status"),
              "generated_at": state_attr("sensor.thornix_soc_status", "generated_at"),
              "summary": state_attr("sensor.thornix_soc_status", "summary") or {},
              "actions": state_attr("sensor.thornix_soc_status", "actions") or [],
              "fleet": state_attr("sensor.thornix_soc_status", "fleet") or {},
              "services": state_attr("sensor.thornix_soc_status", "services") or {},
              "maintenance": state_attr("sensor.thornix_soc_status", "maintenance") or {},
              "deployment": state_attr("sensor.thornix_soc_status", "deployment") or {},
              "security": state_attr("sensor.thornix_soc_status", "security") or {},
              "errors": state_attr("sensor.thornix_soc_status", "errors") or {}
            }
          } | to_json }}
        '';
      };
      rest_command.deck_voice_assistant_update = {
        url = "http://${deckHost}:10701/api/assistant";
        method = "post";
        content_type = "application/json";
        payload = ''
          {{ {
            "stage": stage | default("thinking"),
            "route": route | default(""),
            "tool": tool | default(""),
            "model": model | default(""),
            "voice": voice | default(""),
            "label": label | default(""),
            "detail": detail | default(""),
            "elapsed_ms": elapsed_ms | default(none)
          } | to_json }}
        '';
      };
      rest_command.deck_voice_action = {
        url = "http://${deckHost}:10701/api/action";
        method = "post";
        content_type = "application/json";
        payload = ''
          {{ {
            "action": action,
            "value": value | default(none)
          } | to_json }}
        '';
      };
      automation = [
        {
          id = "pineapple_wireless_security_alert";
          alias = "Pineapple wireless security alert";
          mode = "queued";
          triggers = [
            {
              trigger = "webhook";
              webhook_id = "pineapple-wifi-watch-6f4b2c1d9a8e7350";
              allowed_methods = [ "POST" ];
              local_only = true;
            }
          ];
          actions = [
            {
              action = "persistent_notification.create";
              data = {
                title = "Wireless security alert";
                message = "{{ trigger.json.message | default('Wireless anomaly detected') }}";
                notification_id = "pineapple_wifi_watch";
              };
            }
          ];
        }
        {
          id = "deck_voice_visual_sync";
          alias = "Deck Voice visual data sync";
          mode = "restart";
          triggers = [
            {
              trigger = "homeassistant";
              event = "start";
            }
            {
              trigger = "time_pattern";
              minutes = "/1";
            }
          ];
          actions = [
            {
              action = "weather.get_forecasts";
              target.entity_id = "weather.forecast_home";
              data.type = "daily";
              response_variable = "daily";
              continue_on_error = true;
            }
            {
              action = "rest_command.deck_voice_visual_update";
              data.forecast = ''{{ daily.get("weather.forecast_home", {}).get("forecast", []) if daily is defined else [] }}'';
              continue_on_error = true;
            }
          ];
        }
        {
          id = "thornix_service_unavailable_notification";
          alias = "ThornixOS service unavailable notification";
          mode = "queued";
          max = 20;
          triggers = [
            {
              trigger = "state";
              entity_id = serviceEntityIds;
              to = "unavailable";
              for.minutes = 2;
            }
          ];
          conditions = [
            {
              condition = "template";
              value_template = ''
                {{ trigger.to_state is not none
                   and state_attr(trigger.entity_id, "monitored") == true
                   and states("sensor.thornix_soc_status") not in ["unknown", "unavailable"] }}
              '';
            }
          ];
          actions = [
            {
              action = "persistent_notification.create";
              data = {
                title = ''{{ state_attr(trigger.entity_id, "service_name") or trigger.to_state.name }} is unavailable'';
                message = ''
                  {{ state_attr(trigger.entity_id, "role") or "ThornixOS service" }}
                  has failed its SOC health probe for at least two minutes.
                  {% set url = state_attr(trigger.entity_id, "launch_url") %}
                  {% if url %}[Open service]({{ url }}) · {% endif %}[Open the Services dashboard](/thorn-home/services)
                '';
                notification_id = ''thornix_service_{{ state_attr(trigger.entity_id, "service_id") or trigger.entity_id.split(".")[-1] }}'';
              };
            }
            {
              action = "automation.trigger";
              target.entity_id = "automation.deck_voice_visual_data_sync";
              data.skip_condition = true;
              continue_on_error = true;
            }
          ];
        }
        {
          id = "thornix_service_recovered_notification";
          alias = "ThornixOS service recovered notification";
          mode = "queued";
          max = 20;
          triggers = [
            {
              trigger = "state";
              entity_id = serviceEntityIds;
              from = "unavailable";
              to = "healthy";
            }
          ];
          actions = [
            {
              action = "persistent_notification.dismiss";
              data.notification_id = ''thornix_service_{{ state_attr(trigger.entity_id, "service_id") or trigger.entity_id.split(".")[-1] }}'';
              continue_on_error = true;
            }
            {
              action = "automation.trigger";
              target.entity_id = "automation.deck_voice_visual_data_sync";
              data.skip_condition = true;
              continue_on_error = true;
            }
          ];
        }
        {
          id = "deck_voice_assistant_progress";
          alias = "Deck Voice routed assistant progress";
          mode = "queued";
          max = 10;
          triggers = [
            {
              trigger = "event";
              event_type = "casita_assist_progress";
            }
          ];
          actions = [
            {
              action = "rest_command.deck_voice_assistant_update";
              data = {
                stage = ''{{ trigger.event.data.stage | default("thinking") }}'';
                route = ''{{ trigger.event.data.route | default("") }}'';
                tool = ''{{ trigger.event.data.tool | default("") }}'';
                model = ''{{ trigger.event.data.model | default("") }}'';
                voice = ''{{ trigger.event.data.voice | default("") }}'';
                label = ''{{ trigger.event.data.label | default("") }}'';
                detail = ''{{ trigger.event.data.detail | default("") }}'';
                elapsed_ms = "{{ trigger.event.data.elapsed_ms | default(none) }}";
              };
              continue_on_error = true;
            }
          ];
        }
        {
          id = "deck_voice_casita_profile";
          alias = "Deck Voice - select routed Casita profile";
          mode = "restart";
          triggers = [
            {
              trigger = "homeassistant";
              event = "start";
            }
            {
              trigger = "state";
              entity_id = [
                "sensor.deck_conversation_model"
                "sensor.deck_natural_voice"
              ];
              to = "ready";
            }
          ];
          conditions = [
            {
              condition = "state";
              entity_id = "sensor.deck_conversation_model";
              state = "ready";
            }
            {
              condition = "state";
              entity_id = "sensor.deck_natural_voice";
              state = "ready";
            }
          ];
          actions = [
            {
              wait_template = ''
                {{ "Casita" in (state_attr("select.deck_voice_assistant", "options") | default([], true)) }}
              '';
              timeout = "00:03:00";
              continue_on_timeout = false;
            }
            {
              action = "select.select_option";
              target.entity_id = [
                "select.deck_voice_assistant"
                "select.deck_voice_assistant_2"
              ];
              data.option = "Casita";
            }
          ];
        }
        {
          id = "deck_voice_audio_tuning";
          alias = "Deck Voice audio tuning";
          mode = "restart";
          triggers = [
            {
              trigger = "homeassistant";
              event = "start";
            }
          ];
          actions = [
            {
              wait_template = ''{{ states("number.deck_voice_mic_auto_gain") not in ["unknown", "unavailable"] }}'';
              timeout = "00:02:00";
              continue_on_timeout = false;
            }
            {
              action = "number.set_value";
              target.entity_id = "number.deck_voice_mic_auto_gain";
              data.value = 20;
            }
            {
              action = "number.set_value";
              target.entity_id = "number.deck_voice_mic_volume";
              data.value = 100;
            }
            {
              action = "select.select_option";
              target.entity_id = "select.deck_voice_mic_noise_suppression";
              data.option = "High";
            }
            {
              action = "select.select_option";
              target.entity_id = "select.deck_voice_finished_speaking_detection";
              data.option = "relaxed";
            }
            {
              action = "switch.turn_off";
              target.entity_id = "switch.deck_voice_mute";
            }
            {
              action = "select.select_option";
              target.entity_id = "select.deck_voice_wake_word";
              data.option = "Okay Nabu";
            }
            {
              action = "number.set_value";
              target.entity_id = "number.deck_voice_wake_word_1_sensitivity";
              data.value = 0.85;
            }
            {
              action = "number.set_value";
              target.entity_id = "number.deck_voice_stop_word_sensitivity";
              data.value = 0.5;
            }
          ];
        }
        {
          id = "deck_voice_current_weather";
          alias = "Deck Voice - current weather";
          mode = "single";
          triggers = [
            {
              trigger = "conversation";
              command = [
                "what is the weather [right now]"
                "what's the weather [right now]"
                "how is the weather [outside]"
                "what is [the] temperature outside"
                "what's [the] temperature outside"
                "tell me [the] weather"
                "give me [the] weather report"
              ];
            }
          ];
          actions = [
            {
              set_conversation_response = ''
                {% set entity = "weather.forecast_home" %}
                {% set condition = states(entity) %}
                {% set temperature = state_attr(entity, "temperature") %}
                {% set temperature_unit = state_attr(entity, "temperature_unit") %}
                {% set humidity = state_attr(entity, "humidity") %}
                {% if condition in ["unknown", "unavailable"] or temperature is none %}
                  I can't read the local weather right now.
                {% else %}
                  {% set spoken_condition = condition
                    | replace("partlycloudy", "partly cloudy")
                    | replace("clear-night", "clear")
                    | replace("-", " ")
                    | replace("_", " ") %}
                  {% set spoken_unit = "Fahrenheit" if temperature_unit == "°F"
                    else "Celsius" if temperature_unit == "°C"
                    else "" %}
                  It is {{ spoken_condition }} and
                  {{ temperature | round | int }} degrees {{ spoken_unit }} outside.
                  {% if humidity is number %}
                    Humidity is {{ humidity | round | int }} percent.
                  {% endif %}
                {% endif %}
              '';
            }
          ];
        }
      ]
      ++ import ../../hosts/mitm/voice-automations.nix;
    };
  };

  services.technitium-dns-server = {
    enable = true;
    openFirewall = false;
  };

  # Home Assistant deliberately builds its shared aiohttp TLS context
  # from REQUESTS_CA_BUNDLE (falling back to certifi), so point it at
  # NixOS's system bundle where ThornCloud_CA is installed.
  systemd.services.home-assistant.environment.REQUESTS_CA_BUNDLE =
    "/etc/ssl/certs/ca-certificates.crt";

  services.wyoming = {
    piper.servers.english = {
      enable = true;
      uri = "tcp://0.0.0.0:10200";
      voice = "en_US-lessac-medium";
      lengthScale = 0.92;
      zeroconf.enable = false;
    };
    faster-whisper.servers.english = {
      enable = true;
      uri = "tcp://127.0.0.1:10300";
      model = "base-int8";
      language = "en";
      sttLibrary = "faster-whisper";
      device = "cpu";
      initialPrompt = ''
        Casita. Jamie Duddleston. Thornix. ThornFlix. SOC. Sieve.
        Greenbone. Okay Nabu. Steam Deck. Sony TV. Home Assistant.
        Daily briefing. Weather forecast. Network rack. Security status.
        Mute the TV. Fix the microphone.
      '';
      zeroconf.enable = false;
    };
    openwakeword = {
      enable = true;
      uri = "tcp://127.0.0.1:10400";
      threshold = 0.45;
      refractorySeconds = 1.5;
    };
  };

  systemd.tmpfiles.rules = [
    "L+ /var/lib/hass/thorn-home.yaml - - - - ${inputs.self}/hosts/mitm/thorn-home.yaml"
  ];

  thorn.acme = {
    enable = true;
    domain = "mitm.guildedthorn.arpa";
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."mitm.guildedthorn.arpa" = {
      serverName = "mitm.guildedthorn.arpa";
      forceSSL = true;
      useACMEHost = "mitm.guildedthorn.arpa";
      extraConfig = ''
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "same-origin" always;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:8123";
        proxyWebsockets = true;
      };
      locations."= /health/casita" = {
        proxyPass = "http://127.0.0.1:8123/api/casita/health";
        extraConfig = ''
          allow 172.16.25.51;
          deny all;
        '';
      };
      locations."= /pineapple-wifi-watch" = {
        proxyPass = "http://127.0.0.1:8123/api/webhook/pineapple-wifi-watch-6f4b2c1d9a8e7350";
        extraConfig = ''
          allow 192.168.1.31;
          deny all;
          proxy_set_header Content-Type application/json;
        '';
      };
    };
  };

  services.openssh.settings = {
    KbdInteractiveAuthentication = false;
    PasswordAuthentication = false;
    PermitRootLogin = "prohibit-password";
  };
  users.users.root = {
    initialHashedPassword = "!";
    openssh.authorizedKeys.keys = adminSshKeys;
  };
}
