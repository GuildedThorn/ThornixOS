[
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
]
