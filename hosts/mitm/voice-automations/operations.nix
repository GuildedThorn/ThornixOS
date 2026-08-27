[
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
]
