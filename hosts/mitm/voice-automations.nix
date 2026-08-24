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

  {
    id = "deck_voice_home_status";
    alias = "Deck Voice - home status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "give me [the] home status"
          "give me [a] house report"
          "what is [the] home status"
          "what's going on at home"
          "how is [the] house"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set condition = states("weather.forecast_home")
            | replace("partlycloudy", "partly cloudy")
            | replace("clear-night", "clear")
            | replace("-", " ")
            | replace("_", " ") %}
          {% set temperature = state_attr("weather.forecast_home", "temperature") %}
          {% set person_state = states("person.jamie_duddleston") %}
          {% set streams = states("sensor.thornflix_active_clients") | int(0) %}
          {% set rack_temperature = states("sensor.h5179_f81a_temperature") | float(none) %}
          Home status.
          {% if temperature is number %}
            Outside is {{ condition }} and {{ temperature | round | int }} degrees.
          {% endif %}
          {% if person_state == "home" %}
            Jamie is home.
          {% elif person_state == "not_home" %}
            Jamie is away.
          {% elif person_state not in ["unknown", "unavailable"] %}
            Jamie is at {{ person_state | replace("_", " ") }}.
          {% else %}
            Jamie's location is not reporting.
          {% endif %}
          ThornFlix has {{ streams }} active {{ "stream" if streams == 1 else "streams" }}.
          {% if rack_temperature is number %}
            The network rack is {{ rack_temperature | round | int }} degrees.
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_presence";
    alias = "Deck Voice - presence";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "is Jamie home"
          "where is Jamie"
          "who is home"
          "who's home"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set person_state = states("person.jamie_duddleston") %}
          {% if person_state == "home" %}
            Jamie is home.
          {% elif person_state == "not_home" %}
            Jamie is away.
          {% elif person_state not in ["unknown", "unavailable"] %}
            Jamie is at {{ person_state | replace("_", " ") }}.
          {% else %}
            Jamie's location is not reporting right now.
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_network_rack_status";
    alias = "Deck Voice - network rack status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "what is [the] rack temperature"
          "what's [the] rack temperature"
          "how hot is [the] network rack"
          "what is [the] temperature inside [the] server rack"
          "what's [the] temperature inside [the] server rack"
          "give me [the] network rack status"
          "how is [the] network rack"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set temperature = states("sensor.h5179_f81a_temperature") | float(none) %}
          {% set humidity = states("sensor.h5179_f81a_humidity") | float(none) %}
          {% set battery = states("sensor.h5179_f81a_battery") | float(none) %}
          {% if temperature is not number %}
            The network rack sensor is not reporting right now.
          {% else %}
            The network rack is {{ temperature | round | int }} degrees Fahrenheit.
            {% if humidity is number %}
              Humidity is {{ humidity | round | int }} percent.
            {% endif %}
            {% if battery is number %}
              Sensor battery is {{ battery | round | int }} percent.
            {% endif %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_thornflix_status";
    alias = "Deck Voice - ThornFlix status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "give me [the] ThornFlix status"
          "what is playing on ThornFlix"
          "what's playing on ThornFlix"
          "is anyone watching ThornFlix"
          "how many ThornFlix streams are active"
          "media status"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set streams = states("sensor.thornflix_active_clients") | int(0) %}
          {% set playing = states.media_player
            | selectattr("state", "eq", "playing") | list %}
          ThornFlix has {{ streams }} active {{ "stream" if streams == 1 else "streams" }}.
          {% if playing | count == 0 %}
            No Home Assistant media player is currently reporting playback.
          {% else %}
            {% for player in playing %}
              {{ player.name }} is playing{% set title = state_attr(player.entity_id, "media_title") %}{% if title %}
                {{ title }}{% endif %}{% if loop.last %}.{% else %};{% endif %}
            {% endfor %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_media_control";
    alias = "Deck Voice - media control";
    mode = "single";
    triggers = [
      {
        id = "pause";
        trigger = "conversation";
        command = [
          "pause [the] media"
          "pause [the] video"
          "pause playback"
          "pause [the] TV"
        ];
      }
      {
        id = "resume";
        trigger = "conversation";
        command = [
          "resume [the] media"
          "resume [the] video"
          "resume playback"
          "continue playing"
          "resume [the] TV"
        ];
      }
      {
        id = "stop";
        trigger = "conversation";
        command = [
          "stop [the] media"
          "stop [the] video"
          "stop playback"
          "stop [the] TV"
        ];
      }
      {
        id = "next";
        trigger = "conversation";
        command = [
          "next (track|episode)"
          "skip [this] (track|episode)"
        ];
      }
      {
        id = "previous";
        trigger = "conversation";
        command = [
          "previous (track|episode)"
          "go back [one] (track|episode)"
        ];
      }
    ];
    actions = [
      {
        variables = {
          playing_players = ''{{ states.media_player | selectattr("state", "eq", "playing") | map(attribute="entity_id") | list }}'';
          paused_players = ''{{ states.media_player | selectattr("state", "eq", "paused") | map(attribute="entity_id") | list }}'';
        };
      }
      {
        choose = [
          {
            conditions = [
              {
                condition = "template";
                value_template = ''{{ trigger.id == "pause" and (playing_players | count > 0) }}'';
              }
            ];
            sequence = [
              {
                action = "media_player.media_pause";
                target.entity_id = "{{ playing_players }}";
              }
              { set_conversation_response = "Paused the active media."; }
            ];
          }
          {
            conditions = [
              {
                condition = "template";
                value_template = ''{{ trigger.id == "resume" and (paused_players | count > 0) }}'';
              }
            ];
            sequence = [
              {
                action = "media_player.media_play";
                target.entity_id = "{{ paused_players }}";
              }
              { set_conversation_response = "Resumed the paused media."; }
            ];
          }
          {
            conditions = [
              {
                condition = "template";
                value_template = ''{{ trigger.id == "stop" and (playing_players | count > 0) }}'';
              }
            ];
            sequence = [
              {
                action = "media_player.media_stop";
                target.entity_id = "{{ playing_players }}";
              }
              { set_conversation_response = "Stopped the active media."; }
            ];
          }
          {
            conditions = [
              {
                condition = "template";
                value_template = ''{{ trigger.id == "next" and (playing_players | count > 0) }}'';
              }
            ];
            sequence = [
              {
                action = "media_player.media_next_track";
                target.entity_id = "{{ playing_players }}";
              }
              { set_conversation_response = "Skipping forward."; }
            ];
          }
          {
            conditions = [
              {
                condition = "template";
                value_template = ''{{ trigger.id == "previous" and (playing_players | count > 0) }}'';
              }
            ];
            sequence = [
              {
                action = "media_player.media_previous_track";
                target.entity_id = "{{ playing_players }}";
              }
              { set_conversation_response = "Going back."; }
            ];
          }
        ];
        default = [
          {
            set_conversation_response = "There is no matching active media session right now.";
          }
        ];
      }
    ];
  }

  {
    id = "deck_voice_read_shopping_list";
    alias = "Deck Voice - read shopping list";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "what is on [the] shopping list"
          "what's on [the] shopping list"
          "read [the] shopping list"
          "how many items are on [the] shopping list"
        ];
      }
    ];
    actions = [
      {
        action = "todo.get_items";
        target.entity_id = "todo.shopping_list";
        data.status = "needs_action";
        response_variable = "shopping";
      }
      {
        set_conversation_response = ''
          {% set items = shopping.get("todo.shopping_list", {}).get("items", []) %}
          {% if items | count == 0 %}
            The shopping list is empty.
          {% elif items | count == 1 %}
            The shopping list has one item: {{ items[0].summary }}.
          {% else %}
            The shopping list has {{ items | count }} items:
            {{ items | map(attribute="summary") | join(", ") }}.
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_manage_shopping_list";
    alias = "Deck Voice - manage shopping list";
    mode = "queued";
    triggers = [
      {
        id = "add";
        trigger = "conversation";
        command = [
          "put {item} on [the] shopping list"
        ];
      }
      {
        id = "complete";
        trigger = "conversation";
        command = [
          "mark {item} off [the] shopping list"
          "check off {item} on [the] shopping list"
        ];
      }
      {
        id = "remove";
        trigger = "conversation";
        command = [
          "remove {item} from [the] shopping list"
          "delete {item} from [the] shopping list"
        ];
      }
    ];
    actions = [
      {
        choose = [
          {
            conditions = [ "{{ trigger.id == 'add' }}" ];
            sequence = [
              {
                action = "shopping_list.add_item";
                data.name = "{{ trigger.slots.item }}";
              }
              {
                set_conversation_response = "Added {{ trigger.slots.item }} to the shopping list.";
              }
            ];
          }
          {
            conditions = [ "{{ trigger.id == 'complete' }}" ];
            sequence = [
              {
                action = "shopping_list.complete_item";
                data.name = "{{ trigger.slots.item }}";
              }
              {
                set_conversation_response = "Checked {{ trigger.slots.item }} off the shopping list.";
              }
            ];
          }
          {
            conditions = [ "{{ trigger.id == 'remove' }}" ];
            sequence = [
              {
                action = "shopping_list.remove_item";
                data.name = "{{ trigger.slots.item }}";
              }
              {
                set_conversation_response = "Removed {{ trigger.slots.item }} from the shopping list.";
              }
            ];
          }
        ];
      }
    ];
  }

  {
    id = "deck_voice_sun_times";
    alias = "Deck Voice - sunrise and sunset";
    mode = "single";
    triggers = [
      {
        id = "sunrise";
        trigger = "conversation";
        command = [
          "when is sunrise"
          "what time is sunrise"
          "when does the sun come up"
        ];
      }
      {
        id = "sunset";
        trigger = "conversation";
        command = [
          "when is sunset"
          "what time is sunset"
          "when does the sun go down"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set is_sunrise = trigger.id == "sunrise" %}
          {% set label = "Sunrise" if is_sunrise else "Sunset" %}
          {% set entity = "sensor.sun_next_rising" if is_sunrise else "sensor.sun_next_setting" %}
          {% set value = states(entity) %}
          {% if value in ["unknown", "unavailable"] %}
            I can't read the next {{ label | lower }} right now.
          {% else %}
            {{ label }} is at {{ as_local(as_datetime(value)).strftime("%-I:%M %p") }}.
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_backup_status";
    alias = "Deck Voice - backup status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "give me [the] backup status"
          "what is [the] backup status"
          "what's [the] backup status"
          "when was [the] last backup"
          "did [the] backup run"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set manager = states("sensor.backup_backup_manager_state") %}
          {% set last = states("sensor.backup_last_successful_automatic_backup") %}
          {% set next = states("sensor.backup_next_scheduled_automatic_backup") %}
          {% if manager in ["unknown", "unavailable"] %}
            Home Assistant backup status is unavailable right now.
          {% else %}
            The backup manager is {{ manager | replace("_", " ") }}.
            {% if last not in ["unknown", "unavailable", "none", ""] %}
              The last successful automatic backup was {{ relative_time(as_datetime(last)) }} ago.
            {% endif %}
            {% if next not in ["unknown", "unavailable", "none", ""] %}
              The next backup is scheduled for
              {{ as_local(as_datetime(next)).strftime("%-I:%M %p on %A") }}.
            {% endif %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_storage_status";
    alias = "Deck Voice - storage status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "give me [the] storage status"
          "what is [the] disk status"
          "what's [the] disk status"
          "which disks are full"
          "where is [there] storage pressure"
          "are [any] disks full"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set fleet = state_attr("sensor.thornix_soc_status", "fleet") or {} %}
          {% set disks = fleet.get("disk_attention", []) %}
          {% if states("sensor.thornix_soc_status") in ["unknown", "unavailable"] %}
            The SOC storage summary is unavailable right now.
          {% elif disks | count == 0 %}
            No monitored root disks need attention.
          {% else %}
            {{ disks | count }} monitored root
            {{ "disk needs" if disks | count == 1 else "disks need" }} attention.
            {% for disk in disks[:3] %}
              {{ disk.get("host", "Unknown host") }} is
              {{ disk.get("used_percent", 0) | round(1) }} percent used{% if loop.last %}.{% else %};{% endif %}
            {% endfor %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_deployment_status";
    alias = "Deck Voice - deployment status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "give me [the] deployment status"
          "what is [the] deployment status"
          "what's [the] deployment status"
          "is [the] fleet in sync"
          "are [any] hosts drifted"
          "which hosts need [a] reboot"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set deployment = state_attr("sensor.thornix_soc_status", "deployment") or {} %}
          {% set targets = deployment.get("targets", 0) | int(0) %}
          {% set drifted = deployment.get("drifted_hosts", []) %}
          {% set failures = (deployment.get("deployment_failures", [])
            + deployment.get("build_failures", [])
            + deployment.get("fetch_failures", [])) %}
          {% set reboots = deployment.get("reboot_pending", []) %}
          {% if states("sensor.thornix_soc_status") in ["unknown", "unavailable"] %}
            Deployment status is unavailable right now.
          {% elif drifted | count == 0 and failures | count == 0 %}
            All {{ targets }} deployment targets are aligned with no recorded failures.
            {% if reboots | count > 0 %}
              {{ reboots | join(", ") }} {{ "needs" if reboots | count == 1 else "need" }} a reboot.
            {% else %}
              No hosts are waiting for a reboot.
            {% endif %}
          {% else %}
            {% if drifted | count > 0 %}
              Drifted hosts: {{ drifted | join(", ") }}.
            {% endif %}
            {% if failures | count > 0 %}
              {{ failures | count }} deployment or build failures need review.
            {% endif %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_security_priorities";
    alias = "Deck Voice - security priorities";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "what needs [my] attention"
          "what are [the] security priorities"
          "give me [the] security priorities"
          "what are [the] critical actions"
          "what should I fix [first]"
          "read [the] SOC actions"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set actions = state_attr("sensor.thornix_soc_status", "actions") or [] %}
          {% set urgent = actions
            | rejectattr("severity", "equalto", "maintenance") | list %}
          {% if states("sensor.thornix_soc_status") in ["unknown", "unavailable"] %}
            The SOC action list is unavailable right now.
          {% elif urgent | count == 0 %}
            There are no critical or warning SOC actions right now.
          {% else %}
            There {{ "is" if urgent | count == 1 else "are" }}
            {{ urgent | count }} urgent {{ "action" if urgent | count == 1 else "actions" }}.
            {% for item in urgent[:3] %}
              {{ loop.index }}: {{ item.get("message", "Review the SOC dashboard") }}.
            {% endfor %}
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_microphone_status";
    alias = "Deck Voice - microphone status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "give me [the] microphone status"
          "what is [the] microphone status"
          "what's [the] microphone status"
          "is [the] microphone healthy"
          "is [the] microphone working"
          "voice health"
          "voice diagnostics"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set entity = "sensor.deck_voice_health" %}
          {% set health = states(entity) %}
          {% set audio = state_attr(entity, "audio") or {} %}
          {% set recoveries = state_attr(entity, "recovery_count") | int(0) %}
          {% set volume = states("number.deck_voice_mic_volume") | float(100) %}
          {% set gain = states("number.deck_voice_mic_auto_gain") | int(0) %}
          {% set wake = states("number.deck_voice_wake_word_1_sensitivity") | float(0.85) %}
          {% if health in ["unknown", "unavailable"] %}
            Deck Voice diagnostics are unavailable right now.
          {% elif health == "healthy" %}
            The microphone pipeline is healthy and streaming.
            Capture is {{ "active" if audio.get("capture", false) else "not active" }}.
            Microphone volume is {{ volume | round(0) }} percent with auto gain {{ gain }},
            {{ states("select.deck_voice_mic_noise_suppression") }} noise suppression,
            and wake threshold {{ wake | round(2) }}.
            {% if recoveries > 0 %}
              The watchdog has recovered it {{ recoveries }}
              {{ "time" if recoveries == 1 else "times" }} since the display service started.
            {% endif %}
          {% else %}
            The microphone pipeline is {{ health }}.
            It is {{ "connected" if state_attr(entity, "connected") else "disconnected" }} and
            {{ "streaming" if state_attr(entity, "streaming") else "not streaming" }}.
            Say fix the microphone to force a clean reconnect.
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_microphone_sensitivity";
    alias = "Deck Voice - microphone sensitivity";
    mode = "queued";
    triggers = [
      {
        id = "increase";
        trigger = "conversation";
        command = [
          "make [the] microphone more sensitive"
          "turn up [the] microphone"
          "increase [the] microphone sensitivity"
        ];
      }
      {
        id = "decrease";
        trigger = "conversation";
        command = [
          "make [the] microphone less sensitive"
          "turn down [the] microphone"
          "decrease [the] microphone sensitivity"
        ];
      }
      {
        id = "reset";
        trigger = "conversation";
        command = [
          "reset [the] microphone sensitivity"
          "reset [the] microphone tuning"
        ];
      }
    ];
    actions = [
      {
        variables.current = ''{{ states("number.deck_voice_wake_word_1_sensitivity") | float(0.85) }}'';
      }
      {
        choose = [
          {
            conditions = [ ''{{ trigger.id == "reset" }}'' ];
            sequence = [
              {
                action = "number.set_value";
                target.entity_id = "number.deck_voice_mic_volume";
                data.value = 100;
              }
              {
                action = "number.set_value";
                target.entity_id = "number.deck_voice_mic_auto_gain";
                data.value = 20;
              }
              {
                action = "select.select_option";
                target.entity_id = "select.deck_voice_mic_noise_suppression";
                data.option = "High";
              }
              {
                action = "number.set_value";
                target.entity_id = "number.deck_voice_wake_word_1_sensitivity";
                data.value = 0.85;
              }
              {
                set_conversation_response = "Microphone tuning reset to the far-field profile.";
              }
            ];
          }
        ];
        default = [
          {
            variables.new_level = ''{{ ([0.50, (current | float(0.85)) - 0.05] | max) if trigger.id == "increase" else ([0.98, (current | float(0.85)) + 0.05] | min) }}'';
          }
          {
            action = "number.set_value";
            target.entity_id = "number.deck_voice_wake_word_1_sensitivity";
            data.value = "{{ new_level }}";
          }
          {
            set_conversation_response = ''
              Wake-word sensitivity {{ "increased" if trigger.id == "increase" else "decreased" }}.
              The detection threshold is now {{ new_level | round(2) }}.
            '';
          }
        ];
      }
    ];
  }

  {
    id = "deck_voice_system_status";
    alias = "Deck Voice - system status";
    mode = "single";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "give me [the] system status"
          "what is [the] status"
          "what's [the] status"
          "is Home Assistant healthy"
          "is [the] voice assistant working"
          "assistant status"
          "are all systems online"
        ];
      }
    ];
    actions = [
      {
        set_conversation_response = ''
          {% set voice_health = states("sensor.deck_voice_health") %}
          {% set natural_voice = states("sensor.deck_natural_voice") %}
          {% set backup = states("sensor.backup_backup_manager_state") %}
          {% set soc = states("sensor.thornix_soc_status") %}
          {% set actions = state_attr("sensor.thornix_soc_status", "actions") or [] %}
          Home Assistant is online.
          {% if voice_health == "healthy" %}
            Deck Voice is healthy and streaming.
          {% elif voice_health in ["unknown", "unavailable"] %}
            Deck Voice health telemetry is unavailable.
          {% else %}
            Deck Voice is {{ voice_health }} and its watchdog is handling recovery.
          {% endif %}
          {% if natural_voice == "ready" %}
            My natural local voice is ready too.
          {% elif natural_voice in ["unknown", "unavailable"] %}
            The natural voice is unavailable, so I'll use the fast backup voice.
          {% endif %}
          {% if soc in ["healthy", "warning", "critical"] %}
            SOC status is {{ soc }}.
            {% if soc == "critical" and actions | count > 0 %}
              Top action: {{ actions[0].get("message", "Review the SOC dashboard") }}.
            {% endif %}
          {% endif %}
          {% if backup == "idle" %}
            The backup manager is idle.
          {% elif backup not in ["unknown", "unavailable"] %}
            The backup manager is currently {{ backup | replace("_", " ") }}.
          {% else %}
            Backup status is not available.
          {% endif %}
        '';
      }
    ];
  }

  {
    id = "deck_voice_tv_volume";
    alias = "Deck Voice - TV volume";
    mode = "queued";
    triggers = [
      {
        id = "volume-up";
        trigger = "conversation";
        command = [
          "volume up"
          "turn up [the] [TV] volume"
          "make [the] TV louder"
          "turn it up"
        ];
      }
      {
        id = "volume-down";
        trigger = "conversation";
        command = [
          "volume down"
          "turn down [the] [TV] volume"
          "make [the] TV quieter"
          "turn it down"
        ];
      }
      {
        id = "volume-mute";
        trigger = "conversation";
        command = [
          "mute [the] [TV] volume"
          "mute [the] TV"
          "mute [the] television"
          "newt [the] TV"
        ];
      }
      {
        id = "volume-unmute";
        trigger = "conversation";
        command = [
          "unmute [the] [TV] volume"
          "unmute [the] TV"
        ];
      }
    ];
    actions = [
      {
        action = "rest_command.deck_voice_action";
        data.action = "{{ trigger.id }}";
      }
      {
        set_conversation_response = ''
          {{ {
            "volume-up": "Turning the TV volume up.",
            "volume-down": "Turning the TV volume down.",
            "volume-mute": "Muting the TV.",
            "volume-unmute": "Unmuting the TV."
          }.get(trigger.id, "TV volume adjusted.") }}
        '';
      }
    ];
  }

  {
    id = "deck_voice_tv_volume_set";
    alias = "Deck Voice - set TV volume";
    mode = "queued";
    triggers = [
      {
        trigger = "conversation";
        command = [
          "set [the] [TV] volume to {0..100:volume} [percent]"
          "TV volume {0..100:volume} [percent]"
        ];
      }
    ];
    actions = [
      {
        action = "rest_command.deck_voice_action";
        data = {
          action = "volume-set";
          value = "{{ trigger.slots.volume }}";
        };
      }
      {
        set_conversation_response = "TV volume set to {{ trigger.slots.volume | round | int }} percent.";
      }
    ];
  }

  {
    id = "deck_voice_display_and_recovery";
    alias = "Deck Voice - display and recovery";
    mode = "single";
    triggers = [
      {
        id = "wake";
        trigger = "conversation";
        command = [
          "wake [the] display"
          "wake [the] screen"
          "show [the] dashboard"
          "show me [the] home screen"
        ];
      }
      {
        id = "reconnect";
        trigger = "conversation";
        command = [
          "reconnect [the] voice assistant"
          "restart [the] voice assistant"
          "fix [the] microphone"
          "reconnect [the] microphone"
        ];
      }
      {
        id = "display-restart";
        trigger = "conversation";
        command = [
          "restart [the] dashboard"
          "restart [the] TV app"
          "relaunch [the] TV app"
          "reload [the] voice display"
        ];
      }
      {
        id = "close";
        trigger = "conversation";
        command = [
          "hide [the] dashboard"
          "close [the] dashboard"
          "go [back] to [the] desktop"
          "show [the] desktop"
        ];
      }
    ];
    actions = [
      {
        action = "rest_command.deck_voice_action";
        data.action = "{{ trigger.id }}";
      }
      {
        set_conversation_response = ''
          {{ {
            "wake": "The dashboard is awake.",
            "reconnect": "Reconnecting the Deck voice satellite.",
            "display-restart": "Restarting the TV dashboard.",
            "close": "Closing the dashboard and returning to the desktop."
          }.get(trigger.id, "Display action complete.") }}
        '';
      }
    ];
  }

  {
    id = "deck_voice_local_model_fallback";
    alias = "Deck Voice - local assistant fallback";
    mode = "restart";
    triggers = [
      {
        trigger = "template";
        value_template = ''
          {{ states("sensor.deck_conversation_model") in ["missing", "unavailable"]
             or states("sensor.deck_natural_voice") in ["unknown", "unavailable"] }}
        '';
        for = "00:00:20";
      }
    ];
    conditions = [
      {
        condition = "template";
        value_template = ''
          {{ states("select.deck_voice_assistant") in ["Casita", "Casita Local"]
             or states("select.deck_voice_assistant_2") in ["Casita", "Casita Local"] }}
        '';
      }
    ];
    actions = [
      {
        action = "input_boolean.turn_on";
        target.entity_id = "input_boolean.deck_voice_local_fallback";
      }
      {
        action = "select.select_option";
        target.entity_id = [
          "select.deck_voice_assistant"
          "select.deck_voice_assistant_2"
        ];
        data.option = ''
          {{ "Home Assistant"
             if states("sensor.deck_conversation_model") in ["missing", "unavailable"]
             else "Casita Local" }}
        '';
      }
    ];
  }

  {
    id = "deck_voice_local_model_recovery";
    alias = "Deck Voice - local assistant recovery";
    mode = "restart";
    triggers = [
      {
        trigger = "state";
        entity_id = [
          "sensor.deck_conversation_model"
          "sensor.deck_natural_voice"
        ];
        to = "ready";
        for = "00:00:20";
      }
    ];
    conditions = [
      {
        condition = "state";
        entity_id = "input_boolean.deck_voice_local_fallback";
        state = "on";
      }
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
        action = "select.select_option";
        target.entity_id = [
          "select.deck_voice_assistant"
          "select.deck_voice_assistant_2"
        ];
        data.option = "Casita";
      }
      {
        action = "input_boolean.turn_off";
        target.entity_id = "input_boolean.deck_voice_local_fallback";
      }
    ];
  }
]
