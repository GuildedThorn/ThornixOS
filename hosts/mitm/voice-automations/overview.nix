[
  {
    id = "deck_voice_help";
    alias = "Deck Voice - command help";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "what can you do"
          "what voice commands do you know"
          "list [the] voice commands"
          "voice command help"
          "help me"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          I can report current weather and forecasts; give home, network rack,
          backup, deployment, storage, SOC security, fleet, microphone, presence,
          every ThornixOS service, historical availability, latency and reliability,
          and ThornFlix status; refresh service telemetry; read and manage the shopping list; tell you
          sunrise and sunset times; control active media; adjust the TV volume
          and microphone sensitivity; wake, hide, or restart the dashboard; and
          repair the voice stream. Time and timers work too.
        '';
      }
    ];
  }

  {
    id = "deck_voice_soc_status";
    alias = "Deck Voice - SOC status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "give me [the] SOC status"
          "what is [the] SOC status"
          "what's [the] SOC status"
          "show me [the] SOC [status]"
          "give me [the] security status"
          "the security status"
          "are there [any] security alerts"
          "how are we doing on [the] SOC"
          "how is [the] SOC doing"
          "SOC"
          "how is [the] fleet"
          "give me [the] fleet status"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set entity = "sensor.thornix_soc_status" %}
          {% set status = states(entity) %}
          {% set summary = state_attr(entity, "summary") or {} %}
          {% set actions = state_attr(entity, "actions") or [] %}
          {% set fleet = state_attr(entity, "fleet") or {} %}
          {% set services = state_attr(entity, "services") or {} %}
          {% set security = state_attr(entity, "security") or {} %}
          {% set node_total = fleet.get("node_targets", 0) | int(0) %}
          {% set node_down = fleet.get("down_hosts", []) | count %}
          {% set service_total = services.get("checked", 0) | int(0) %}
          {% set service_down = services.get("unavailable", []) | count %}
          {% if status in ["unknown", "unavailable"] %}
            The SOC summary is not reachable right now.
          {% else %}
            SOC status is {{ status }}. {{ summary.get("headline", "") }}.
            {{ node_total - node_down }} of {{ node_total }} monitored hosts and
            {{ service_total - service_down }} of {{ service_total }} service probes are online.
            In the last 24 hours, SOC recorded
            {{ security.get("suricata_alerts", 0) | int(0) }} Suricata alerts and
            {{ security.get("zeek_notices", 0) | int(0) }} Zeek notices.
            {% set critical = actions | selectattr("severity", "equalto", "critical") | list %}
            {% if critical | count > 0 %}
              Top priority: {{ critical[0].get("message", "Review the SOC dashboard") }}.
            {% endif %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_thornix_service_status";
    alias = "Deck Voice - ThornixOS service catalog";
    mode = "queued";
    triggers = [
      {
        id = "summary";
        trigger = "conversation";
        command = [
          "how are [all] [of] my services"
          "give me [the] service status"
          "are [all] my services online"
          "check [all] [the] ThornixOS services"
          "how is [the] service fleet"
        ];
      }
      {
        id = "catalog";
        trigger = "conversation";
        command = [
          "list [all] my services"
          "what [ThornixOS] services do I have"
          "show [me] [the] service catalog"
          "which services are integrated"
        ];
      }
      {
        id = "attention";
        trigger = "conversation";
        command = [
          "which services need [my] attention"
          "are any [of my] services down"
          "what services are degraded"
          "show me [the] unreliable services"
          "which services are missing [their] reliability target"
        ];
      }
      {
        id = "slowest";
        trigger = "conversation";
        command = [
          "which service is [the] slowest"
          "what are [the] slowest services"
          "give me [the] service latency"
          "how fast are [my] services"
        ];
      }
      {
        id = "staged";
        trigger = "conversation";
        command = [
          "which services are not monitored"
          "which services are staged"
          "what still needs monitoring"
        ];
      }
      {
        id = "role";
        trigger = "conversation";
        command = [
          "what does {service} do"
          "what is {service} for"
          "tell me about {service}"
        ];
      }
      {
        id = "availability";
        trigger = "conversation";
        command = [
          "what is {service} uptime"
          "what is {service} availability"
          "how reliable is {service}"
        ];
      }
      {
        id = "single";
        trigger = "conversation";
        command = [
          "is {service} online"
          "is [the] {service} service online"
          "check [the] {service} service"
          "what is [the] {service} service status"
          "what is [the] status of {service}"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set entities = expand("group.thornix_services") | list %}
          {% if entities | count == 0 %}
            The ThornixOS service catalog is unavailable right now.
          {% elif trigger.id == "catalog" %}
            {% set names = namespace(items=[]) %}
            {% for entity in entities %}
              {% set names.items = names.items + [state_attr(entity.entity_id, "service_name") or entity.name] %}
            {% endfor %}
            I have {{ entities | count }} integrated services:
            {{ names.items | sort | join(", ") }}.
          {% elif trigger.id == "summary" %}
            {% set totals = namespace(monitored=0, healthy=0, attention=[]) %}
            {% for entity in entities %}
              {% if entity.state != "not_monitored" %}
                {% set totals.monitored = totals.monitored + 1 %}
                {% if entity.state == "healthy" %}
                  {% set totals.healthy = totals.healthy + 1 %}
                {% else %}
                  {% set totals.attention = totals.attention + [state_attr(entity.entity_id, "service_name") or entity.name] %}
                {% endif %}
              {% endif %}
            {% endfor %}
            {{ totals.healthy }} of {{ totals.monitored }} monitored services are healthy.
            {% if totals.attention | count > 0 %}
              Attention is needed on {{ totals.attention | join(", ") }}.
            {% elif totals.monitored < entities | count %}
              The remaining {{ (entities | count) - totals.monitored }} integrated
              {{ "service is" if (entities | count) - totals.monitored == 1 else "services are" }}
              staged but not monitored yet.
            {% else %}
              Every integrated service is online.
            {% endif %}
          {% elif trigger.id == "attention" %}
            {% set attention = namespace(items=[]) %}
            {% for entity in entities %}
              {% set slo = state_attr(entity.entity_id, "slo_status") or "unknown" %}
              {% if entity.state not in ["healthy", "not_monitored"]
                    or slo in ["down", "breached", "at_risk"] %}
                {% set attention.items = attention.items + [{
                  "name": state_attr(entity.entity_id, "service_name") or entity.name,
                  "state": entity.state,
                  "slo": slo
                }] %}
              {% endif %}
            {% endfor %}
            {% if attention.items | count == 0 %}
              No monitored service is down, slow, or missing its reliability target.
            {% else %}
              {{ attention.items | count }}
              {{ "service needs" if attention.items | count == 1 else "services need" }} attention.
              {% for item in attention.items[:5] %}
                {{ item.name }} is {{ item.state | replace("_", " ") }}
                with reliability {{ item.slo | replace("_", " ") }}{% if loop.last %}.{% else %};{% endif %}
              {% endfor %}
            {% endif %}
          {% elif trigger.id == "slowest" %}
            {% set ranked = namespace(items=[]) %}
            {% for entity in entities %}
              {% set p95 = state_attr(entity.entity_id, "latency_p95_seconds") | float(none) %}
              {% set current = state_attr(entity.entity_id, "latency_seconds") | float(none) %}
              {% set seconds = p95 if p95 is number else current %}
              {% if seconds is number and entity.state != "not_monitored" %}
                {% set ranked.items = ranked.items + [{
                  "name": state_attr(entity.entity_id, "service_name") or entity.name,
                  "seconds": seconds,
                  "kind": "95th percentile" if p95 is number else "current"
                }] %}
              {% endif %}
            {% endfor %}
            {% set slowest = ranked.items | sort(attribute="seconds", reverse=true) %}
            {% if slowest | count == 0 %}
              Service latency history is not available yet.
            {% else %}
              The slowest measured services are
              {% for item in slowest[:3] %}
                {{ item.name }} at {{ (item.seconds * 1000) | round | int }} milliseconds
                {{ item.kind }}{% if loop.last %}.{% else %};{% endif %}
              {% endfor %}
            {% endif %}
          {% elif trigger.id == "staged" %}
            {% set staged = entities | selectattr("state", "equalto", "not_monitored") | list %}
            {% if staged | count == 0 %}
              Every integrated service has an active SOC health probe.
            {% else %}
              {{ staged | count }} {{ "service is" if staged | count == 1 else "services are" }} staged:
              {% for entity in staged %}
                {{ state_attr(entity.entity_id, "service_name") or entity.name }}{% if loop.last %}.{% else %},{% endif %}
              {% endfor %}
            {% endif %}
          {% else %}
            {% set requested = trigger.slots.service | default("") | lower | trim %}
            {% set matches = namespace(items=[]) %}
            {% for entity in entities %}
              {% set service_id = (state_attr(entity.entity_id, "service_id") or "") | lower %}
              {% set service_name = (state_attr(entity.entity_id, "service_name") or entity.name) | lower %}
              {% set service_host = (state_attr(entity.entity_id, "host") or "") | lower %}
              {% set role = (state_attr(entity.entity_id, "role") or "") | lower %}
              {% set aliases = (state_attr(entity.entity_id, "aliases") or "") | lower %}
              {% if requested in [service_id, service_name, service_host]
                    or requested in aliases
                    or requested in (service_id ~ " " ~ service_name ~ " " ~ service_host ~ " " ~ role ~ " " ~ aliases) %}
                {% set matches.items = matches.items + [entity] %}
              {% endif %}
            {% endfor %}
            {% if matches.items | count == 0 %}
              I don't recognize {{ trigger.slots.service }} in the ThornixOS service catalog.
              Say, list my services, to hear the available names.
            {% else %}
              {% set entity = matches.items[0] %}
              {% set name = state_attr(entity.entity_id, "service_name") or entity.name %}
              {% set role = state_attr(entity.entity_id, "role") or "ThornixOS service" %}
              {% set latency = state_attr(entity.entity_id, "latency_seconds") | float(none) %}
              {% set availability = state_attr(entity.entity_id, "availability_percent") | float(none) %}
              {% set p95 = state_attr(entity.entity_id, "latency_p95_seconds") | float(none) %}
              {% set slo = state_attr(entity.entity_id, "slo_status") or "unknown" %}
              {% set window = state_attr(entity.entity_id, "reliability_window") or "24 hours" %}
              {% set http_status = state_attr(entity.entity_id, "http_status") %}
              {% if trigger.id == "role" %}
                {{ name }} provides {{ role | lower }} on the {{ state_attr(entity.entity_id, "host") or name }} host.
                It is currently {{ entity.state | replace("_", " ") }}.
              {% elif trigger.id == "availability" %}
                {% if entity.state == "not_monitored" %}
                  {{ name }} is integrated, but it does not have reliability history yet.
                {% elif availability is number %}
                  Over the last {{ window }}, {{ name }} availability is
                  {{ availability | round(3) }} percent. Reliability is
                  {{ slo | replace("_", " ") }}{% if p95 is number %}, with
                  {{ (p95 * 1000) | round | int }} millisecond 95th percentile latency{% endif %}.
                {% else %}
                  {{ name }} is {{ entity.state | replace("_", " ") }}, but its reliability history is not available yet.
                {% endif %}
              {% elif entity.state == "healthy" %}
                {{ name }} is online. {{ role }} is healthy{% if latency is number %},
                responding in {{ (latency * 1000) | round | int }} milliseconds{% endif %}{% if http_status not in [none, "None", "unknown", "unavailable"] %}
                with HTTP {{ http_status }}{% endif %}.
                {% if availability is number %}
                  {{ window }} availability is {{ availability | round(3) }} percent,
                  with reliability {{ slo | replace("_", " ") }}.
                {% endif %}
              {% elif entity.state == "not_monitored" %}
                {{ name }} is integrated as {{ role }}, but its SOC health probe is not active yet.
              {% else %}
                {{ name }} is {{ entity.state | replace("_", " ") }}.
                Its role is {{ role }}. Check the SOC service dashboard for details.
              {% endif %}
            {% endif %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_refresh_service_status";
    alias = "Deck Voice - refresh ThornixOS service status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "refresh [the] service status"
          "refresh [all] [my] services"
          "check [the] services again"
          "rescan [the] services"
        ];
      }
    ];
    actions = [
      {
        action = "homeassistant.update_entity";
        target.entity_id = "sensor.thornix_soc_status";
      }
      {
        action = "automation.trigger";
        target.entity_id = "automation.deck_voice_visual_data_sync";
        data.skip_condition = true;
        continue_on_error = true;
      }
      {
        set_conversation_response = ''
          {% set services = state_attr("sensor.thornix_soc_status", "services") or {} %}
          {% set checked = services.get("checked", 0) | int(0) %}
          {% set healthy = services.get("healthy", 0) | int(0) %}
          Service telemetry is refreshed. {{ healthy }} of {{ checked }} monitored
          services are online, and the Sony display has the latest snapshot.
        '';
      }
    ];
  }

  {
    id = "deck_voice_daily_briefing";
    alias = "Deck Voice - daily briefing";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "good morning"
          "give me [my] daily briefing"
          "give me [my] daily breathing"
          "daily briefing"
          "daily breathing"
          "give me [my] morning briefing"
          "what's happening today"
          "what is happening today"
        ];
      }
    ];
    actions = [
      {
        action = "weather.get_forecasts";
        target.entity_id = "weather.forecast_home";
        data.type = "daily";
        response_variable = "daily";
      }
      {
        set_conversation_response = ''
          {% set raw_condition = states("weather.forecast_home") %}
          {% set current_condition = raw_condition
            | replace("partlycloudy", "partly cloudy")
            | replace("clear-night", "clear")
            | replace("-", " ")
            | replace("_", " ") %}
          {% set current_temperature = state_attr("weather.forecast_home", "temperature") %}
          {% set forecasts = daily.get("weather.forecast_home", {}).get("forecast", []) %}
          {% set forecast = forecasts[0] if forecasts | count > 0 else none %}
          {% set sunset_value = states("sensor.sun_next_setting") %}
          {% set soc_status = states("sensor.thornix_soc_status") %}
          {% set soc_summary = state_attr("sensor.thornix_soc_status", "summary") or {} %}
          {% set soc_actions = state_attr("sensor.thornix_soc_status", "actions") or [] %}
          {% set soc_fleet = state_attr("sensor.thornix_soc_status", "fleet") or {} %}
          {% set soc_services = state_attr("sensor.thornix_soc_status", "services") or {} %}
          Good morning, Jamie. Here's the short version.
          {% if current_temperature is number %}
            It is {{ current_condition }} and {{ current_temperature | round | int }} degrees outside.
          {% endif %}
          {% if forecast %}
            Today's high is {{ forecast.get("temperature") | round | int }} degrees
            and the low is {{ forecast.get("templow") | round | int }}.
          {% endif %}
          {% if sunset_value not in ["unknown", "unavailable"] %}
            Sunset is at {{ as_local(as_datetime(sunset_value)).strftime("%-I:%M %p") }}.
          {% endif %}
          {% set streams = states("sensor.thornflix_active_clients") | int(0) %}
          {% if streams == 0 %}
            ThornFlix is quiet right now, with no active streams.
          {% else %}
            ThornFlix has {{ streams }} active {{ "stream" if streams == 1 else "streams" }}.
          {% endif %}
          {% if is_state("sensor.deck_conversation_model", "ready")
                and is_state("sensor.deck_natural_voice", "ready") %}
            I'm fully local, including my natural voice.
          {% elif is_state("sensor.deck_conversation_model", "ready") %}
            My local conversation model is ready, and I'm using the fast backup voice.
          {% else %}
            I'm using Home Assistant's native fallback for now.
          {% endif %}
          {% if soc_status in ["unknown", "unavailable"] %}
            The SOC summary is unavailable right now.
          {% else %}
            {% set host_total = soc_fleet.get("node_targets", 0) | int(0) %}
            {% set host_down = soc_fleet.get("down_hosts", []) | count %}
            {% set service_total = soc_services.get("checked", 0) | int(0) %}
            {% set service_down = soc_services.get("unavailable", []) | count %}
            {% set slo_attention = soc_services.get("slo_attention", []) %}
            SOC status is {{ soc_status }}.
            {% if host_total > 0 and service_total > 0 %}
              {{ host_total - host_down }} of {{ host_total }} monitored hosts and
              {{ service_total - service_down }} of {{ service_total }} service probes are online.
            {% endif %}
            {% if slo_attention | count > 0 %}
              {{ slo_attention | count }} service
              {{ "reliability target needs" if slo_attention | count == 1 else "reliability targets need" }} review.
            {% elif service_total > 0 %}
              Every monitored service meets its reliability target.
            {% endif %}
            {% if soc_status in ["warning", "critical"] and soc_actions | count > 0 %}
              Top priority: {{ soc_actions[0].get("message", "Review the SOC dashboard") }}.
            {% elif soc_summary.get("headline") %}
              {{ soc_summary.get("headline") }}.
            {% endif %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_weather_forecast";
    alias = "Deck Voice - weather forecast";
    mode = "single";
    triggers = [
      {
        id = "today";
        trigger = "conversation";
        command = [
          "what is today's forecast"
          "what's today's forecast"
          "what will [the] weather be [like] today"
          "give me today's forecast"
        ];
      }
      {
        id = "tomorrow";
        trigger = "conversation";
        command = [
          "what is tomorrow's forecast"
          "what's tomorrow's forecast"
          "what's the forecast tomorrow"
          "what is the forecast tomorrow"
          "what's the weather like tomorrow"
          "what will [the] weather be [like] tomorrow"
          "give me tomorrow's forecast"
        ];
      }
      {
        id = "outlook";
        trigger = "conversation";
        command = [
          "give me [the] three day forecast"
          "what is [the] three day forecast"
          "what's [the] three day forecast"
          "give me [the] weather outlook"
          "what is [the] weather outlook"
        ];
      }
    ];
    actions = [
      {
        action = "weather.get_forecasts";
        target.entity_id = "weather.forecast_home";
        data.type = "daily";
        response_variable = "daily";
      }
      {
        set_conversation_response = ''
          {% set forecasts = daily.get("weather.forecast_home", {}).get("forecast", []) %}
          {% if trigger.id == "outlook" %}
            {% if forecasts | count == 0 %}
              I can't read the weather outlook right now.
            {% else %}
              Here is the three day outlook.
              {% for forecast in forecasts[:3] %}
                {% set condition = forecast.get("condition", "unknown")
                  | replace("partlycloudy", "partly cloudy")
                  | replace("clear-night", "clear")
                  | replace("-", " ")
                  | replace("_", " ") %}
                {{ as_local(as_datetime(forecast.get("datetime"))).strftime("%A") }}:
                {{ condition }}, high {{ forecast.get("temperature") | round | int }},
                low {{ forecast.get("templow") | round | int }}{% if loop.last %}.{% else %};{% endif %}
              {% endfor %}
            {% endif %}
          {% else %}
            {% set index = 1 if trigger.id == "tomorrow" else 0 %}
            {% set label = "Tomorrow" if index == 1 else "Today" %}
            {% if forecasts | count <= index %}
              I can't read the {{ label | lower }} forecast right now.
            {% else %}
              {% set forecast = forecasts[index] %}
              {% set condition = forecast.get("condition", "unknown")
                | replace("partlycloudy", "partly cloudy")
                | replace("clear-night", "clear")
                | replace("-", " ")
                | replace("_", " ") %}
              {{ label }} will be {{ condition }}, with a high of
              {{ forecast.get("temperature") | round | int }} degrees and a low of
              {{ forecast.get("templow") | round | int }} degrees.
            {% endif %}
          {% endif %}
        '';
      }
    ];
  }
]
