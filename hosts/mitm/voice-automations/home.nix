[
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
]
