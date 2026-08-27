[
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
