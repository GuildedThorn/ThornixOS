{
  config,
  inputs,
  lib,
  pkgs,
}:
let
  cfg = config.thorn.programs.opencode;
  jsonFormat = pkgs.formats.json { };

  readUvProject = source: (builtins.fromTOML (builtins.readFile "${source}/pyproject.toml")).project;
  jcodemunchSource = inputs."opencode-jcodemunch-src";
  jcodemunchProject = readUvProject jcodemunchSource;

  mkLockedUvTool =
    {
      executable,
      name,
      source,
      wheel,
    }:
    let
      project = readUvProject source;
      requirements =
        pkgs.runCommand "${name}-${project.version}-requirements.txt"
          {
            nativeBuildInputs = [ pkgs.uv ];
          }
          ''
            export HOME="$TMPDIR/home"
            export UV_CACHE_DIR="$TMPDIR/uv-cache"
            export UV_NO_PROGRESS=1
            export UV_OFFLINE=1
            mkdir -p "$HOME"

            uv export \
              --project ${source} \
              --frozen \
              --no-dev \
              --no-emit-project \
              --output-file "$out"

            # Hashes make the exported transitive lock meaningful at the
            # runtime hydration boundary, not merely a version constraint.
            grep -q -- '--hash=' "$out"
          '';
      fetchedWheel = pkgs.fetchurl {
        inherit (wheel) url hash;
        name = wheel.fileName;
      };
      wheelDirectory = pkgs.linkFarm "${name}-${project.version}-wheel" [
        {
          inherit (wheel) name;
          path = fetchedWheel;
        }
      ];
      wheelPath =
        assert lib.hasInfix "-${project.version}-" wheel.fileName;
        "${wheelDirectory}/${wheel.fileName}";
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.python313
        pkgs.uv
      ];
      text = ''
        export UV_CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/opencode/uv"
        export UV_NO_CONFIG=1
        export UV_NO_PROGRESS=1
        export UV_PYTHON_DOWNLOADS=never
        export UV_QUIET=1
        export LD_LIBRARY_PATH="${
          lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ]
        }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        tool_state="$UV_CACHE_DIR/managed/${name}-${project.version}"
        export UV_TOOL_DIR="$tool_state/environments"
        export UV_TOOL_BIN_DIR="$tool_state/bin"
        executable_path="$UV_TOOL_BIN_DIR/${executable}"

        # Resolve once into a versioned environment, then bypass uv on the
        # hot path. MCP clients are sensitive to startup latency and stdout
        # must contain protocol frames only.
        if [ ! -x "$executable_path" ]; then
          mkdir -p "$UV_TOOL_BIN_DIR"
          if ! UV_OFFLINE=1 ${lib.getExe pkgs.uv} tool install \
            --quiet \
            --python ${lib.getExe pkgs.python313} \
            --with-requirements ${requirements} \
            ${wheelPath}; then
            ${lib.getExe pkgs.uv} tool install \
              --quiet \
              --python ${lib.getExe pkgs.python313} \
              --with-requirements ${requirements} \
              ${wheelPath}
          fi
        fi

        exec "$executable_path" "$@"
      '';
      meta = {
        mainProgram = name;
        description = "Locked ${project.name} ${project.version} launcher for OpenCode";
      };
    };

  jcodemunch = mkLockedUvTool {
    name = "jcodemunch-mcp";
    executable = "jcodemunch-mcp";
    source = jcodemunchSource;
    wheel = {
      fileName = "jcodemunch_mcp-1.108.279-py3-none-any.whl";
      name = "jcodemunch_mcp-1.108.279-py3-none-any.whl";
      url = "https://files.pythonhosted.org/packages/b7/78/23c7ef39789c3a56d40e9ad4f7d978a776190c494a52b0ba7938697f551f/jcodemunch_mcp-1.108.279-py3-none-any.whl";
      hash = "sha256-0ZKZipq82K+hR08qFjfiYKmrSP3QCAtraQYysq8eMPE=";
    };
  };

  serena = mkLockedUvTool {
    name = "serena";
    executable = "serena";
    source = inputs."opencode-serena-src";
    wheel = {
      fileName = "serena_agent-1.7.0-py3-none-any.whl";
      name = "serena_agent-1.7.0-py3-none-any.whl";
      url = "https://files.pythonhosted.org/packages/95/c1/edd38220ce54fe37999d5b4a0790e6cfcc3557f71a8f47cf850fc079769b/serena_agent-1.7.0-py3-none-any.whl";
      hash = "sha256-bb8UWWcNlvsFlfhJMq3vNCYKb+FLpRNbkB/bPIx26JE=";
    };
  };

  graphify = mkLockedUvTool {
    name = "graphify";
    executable = "graphify";
    source = inputs."opencode-graphify-src";
    wheel = {
      fileName = "graphifyy-0.9.43-py3-none-any.whl";
      name = "graphifyy-0.9.43-py3-none-any.whl";
      url = "https://files.pythonhosted.org/packages/65/2c/04bd7ddb33ac23c8b13f10e1fcfbc767b10269e6bdee10dafc7c8f7b66d1/graphifyy-0.9.43-py3-none-any.whl";
      hash = "sha256-oosLgB7JPEBsf8eYUwBmMoDdOraPb1J6dpLU/K1LQAs=";
    };
  };

  integrationPackages = lib.unique (
    lib.optionals cfg.integrations.jcodemunch.enable [ jcodemunch ]
    ++ lib.optionals cfg.integrations.serena.enable [ serena ]
    ++ lib.optionals cfg.integrations.context7.enable [ cfg.integrations.context7.package ]
    ++ lib.optionals cfg.integrations.graphify.enable [ graphify ]
  );

  opencodeExtraPackages = lib.unique (cfg.extraPackages ++ integrationPackages);

  jcodemunchConfig = jsonFormat.generate "jcodemunch-config.jsonc" {
    inherit (jcodemunchProject) version;
    tool_profile = "core";
    compact_schemas = true;
    server_output = "adaptive";
    meta_fields = [ ];
    context_providers = false;
    extra_ignore_patterns = [
      ".serena/"
      "graphify-out/"
    ];
    trusted_folders = cfg.integrations.jcodemunch.trustedFolders;
    trusted_folders_whitelist_mode = true;
    use_ai_summaries = false;
    allow_paid_summaries = false;
    allow_remote_summarizer = false;
    perf_telemetry_enabled = false;
    redact_source_root = true;
    share_savings = false;
  };

  managedMcpSettings =
    lib.optionalAttrs cfg.integrations.jcodemunch.enable {
      jcodemunch = {
        type = "local";
        command = [ (lib.getExe jcodemunch) ];
        enabled = true;
        timeout = cfg.integrations.mcpTimeout;
        environment = {
          JCODEMUNCH_HANDSHAKE_TIMEOUT = "0";
        };
      };
    }
    // lib.optionalAttrs cfg.integrations.serena.enable {
      serena = {
        type = "local";
        command = [
          (lib.getExe serena)
          "start-mcp-server"
          "--context"
          "ide"
          "--project-from-cwd"
          "--enable-web-dashboard"
          "false"
          "--enable-gui-log-window"
          "false"
          "--open-web-dashboard"
          "false"
        ];
        enabled = true;
        timeout = cfg.integrations.mcpTimeout;
      };
    }
    // lib.optionalAttrs cfg.integrations.context7.enable {
      context7 = {
        type = "local";
        command = [ (lib.getExe cfg.integrations.context7.package) ];
        enabled = true;
        timeout = cfg.integrations.mcpTimeout;
        environment.CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
      };
    };

  hasRetrievalIntegrations =
    cfg.integrations.jcodemunch.enable
    || cfg.integrations.serena.enable
    || cfg.integrations.context7.enable
    || cfg.integrations.graphify.enable;

  retrievalInstructionsPath = "${config.xdg.configHome}/opencode/instructions/retrieval.md";

  defaultManagedSettings = {
    # The package is upgraded by Nix, never by a self-mutating installer.
    autoupdate = false;
    share = "disabled";
    snapshot = true;
    formatter = true;
    lsp = true;
    subagent_depth = 2;
    shell = lib.getExe pkgs.zsh;

    server = {
      hostname = "127.0.0.1";
      mdns = false;
    };

    permission = {
      doom_loop = "ask";
      external_directory = "ask";
    };

    compaction = {
      auto = true;
      prune = true;
      tail_turns = 4;
    };

    watcher.ignore = [
      ".devenv/**"
      ".direnv/**"
      ".git/**"
      ".jj/**"
      "graphify-out/**"
      "node_modules/**"
      "result"
      "result-*"
    ];
  }
  // lib.optionalAttrs cfg.integrations.codex.enable {
    model = cfg.integrations.codex.model;
    small_model = cfg.integrations.codex.smallModel;
  }
  // lib.optionalAttrs hasRetrievalIntegrations {
    instructions = [ retrievalInstructionsPath ];
  }
  // lib.optionalAttrs (managedMcpSettings != { }) {
    mcp = managedMcpSettings;
  };

  defaultTuiSettings = {
    diff_style = "auto";
    mouse = true;
    scroll_speed = 3;
    scroll_acceleration.enabled = true;

    prompt = {
      max_height = 12;
      max_width = "auto";
    };

    attention = {
      enabled = true;
      notifications = true;
      sound = false;
    };
  };

  managedSettings = {
    "$schema" = "https://opencode.ai/config.json";
  }
  // lib.recursiveUpdate defaultManagedSettings cfg.managedSettings;

  renderedManagedSettings = jsonFormat.generate "opencode-nix-managed-unchecked.json" managedSettings;

  modelsDevSchema = pkgs.fetchurl {
    url = "https://models.dev/model-schema.json";
    hash = "sha256-/95TguwPwcmZOxgI7gu14PhBA0RviNuEJhZuApP9dGQ=";
  };

  # OpenCode deliberately references models.dev from its bundled schema.
  # Rewrite only that reference to a content-addressed local copy so model
  # validation is strict without requiring network access in the sandbox.
  opencodeConfigSchema = pkgs.runCommand "opencode-config-schema-offline.json" { } ''
    substitute ${cfg.package}/share/opencode/config.json "$out" \
      --replace-fail \
        'https://models.dev/model-schema.json#/$defs/Model' \
        'file://${modelsDevSchema}#/$defs/Model'
  '';

  # Make schema drift a build failure instead of a surprise on next launch.
  validatedManagedSettings =
    pkgs.runCommand "opencode-nix-managed.json"
      {
        nativeBuildInputs = [ pkgs.check-jsonschema ];
      }
      ''
        check-jsonschema \
          --schemafile ${opencodeConfigSchema} \
          ${renderedManagedSettings}
        cp ${renderedManagedSettings} "$out"
      '';

  opencodeIntegrationsSync = pkgs.writeShellApplication {
    name = "opencode-integrations-sync";
    runtimeInputs = integrationPackages;
    text = ''
      printf 'Hydrating locked OpenCode integrations\n'
      printf '  cache: %s\n' "''${XDG_CACHE_HOME:-$HOME/.cache}/opencode/uv"

      ${lib.optionalString cfg.integrations.jcodemunch.enable ''
        printf '  jCodeMunch: '
        ${lib.getExe jcodemunch} --version
      ''}
      ${lib.optionalString cfg.integrations.serena.enable ''
        printf '  Serena: '
        ${lib.getExe serena} --version
      ''}
      ${lib.optionalString cfg.integrations.context7.enable ''
        ${lib.getExe cfg.integrations.context7.package} --help >/dev/null
        printf '  Context7: ready (%s)\n' ${lib.escapeShellArg (lib.getVersion cfg.integrations.context7.package)}
      ''}
      ${lib.optionalString cfg.integrations.graphify.enable ''
        printf '  Graphify: '
        ${lib.getExe graphify} --version
      ''}

      printf 'All enabled integrations are ready.\n'
    '';
  };

  extraPackageExecutables = map (
    package: package.meta.mainProgram or (lib.getName package)
  ) opencodeExtraPackages;

  managedAssetPaths = [
    "agents/thornix-auditor.md"
    "commands/thornix-audit.md"
    "commands/thornix-check.md"
  ]
  ++ lib.optionals hasRetrievalIntegrations [ "instructions/retrieval.md" ]
  ++ lib.optionals cfg.integrations.graphify.enable [
    "commands/graphify.md"
    "plugins/nix-graphify.js"
    "skills/graphify/SKILL.md"
  ];

  managedMcpNames = lib.attrNames managedMcpSettings;

  opencodeDoctor = pkgs.writeShellApplication {
    name = "opencode-doctor";
    runtimeInputs = [
      pkgs.check-jsonschema
      pkgs.coreutils
      pkgs.jq
    ]
    ++ opencodeExtraPackages;
    text = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
      global_config="$config_dir/opencode.json"
      managed_config="$config_dir/nix-managed.json"
      tui_config="$config_dir/tui.json"
      theme_config="$config_dir/themes/stylix.json"
      plugin_manifest="$config_dir/package.json"
      auth_file="''${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
      model_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/opencode/models.json"
      jcodemunch_config="$HOME/.code-index/config.jsonc"
      config_schema="${opencodeConfigSchema}"
      tui_schema="${cfg.package}/share/opencode/tui.json"
      failures=0

      pass() { printf '  [ok]   %s\n' "$1"; }
      warn() { printf '  [warn] %s\n' "$1"; }
      fail() {
        printf '  [fail] %s\n' "$1"
        failures=$((failures + 1))
      }

      check_json() {
        label=$1
        schema=$2
        path=$3

        if [ ! -e "$path" ]; then
          fail "$label missing: $path"
        elif check-jsonschema --schemafile "$schema" "$path" >/dev/null; then
          pass "$label matches schema"
        else
          fail "$label failed schema validation"
          check-jsonschema --schemafile "$schema" "$path" || true
        fi
      }

      printf 'OpenCode doctor\n'
      printf '  binary:  %s\n' "$(command -v opencode)"
      printf '  version: %s\n' "$(opencode --version)"
      printf '  config:  %s\n' "$config_dir"

      check_json "Nix-managed config" "$config_schema" "$managed_config"
      check_json "TUI config" "$tui_schema" "$tui_config"

      for relative_asset in ${lib.escapeShellArgs managedAssetPaths}; do
        asset="$config_dir/$relative_asset"
        if [ -e "$asset" ]; then
          pass "managed asset exists: $relative_asset"
        else
          fail "managed asset missing: $asset"
        fi
      done

      if [ -e "$global_config" ]; then
        check_json "writable global config" "$config_schema" "$global_config"
        if [ -w "$global_config" ]; then
          pass "global config remains writable for plugins"
        else
          fail "global config is not writable: $global_config"
        fi

        while IFS= read -r plugin; do
          case "$plugin" in
            ./*)
              plugin_path="$config_dir/''${plugin#./}"
              if [ -e "$plugin_path" ]; then
                pass "plugin exists: $plugin"
              else
                fail "plugin missing: $plugin_path"
              fi
              ;;
          esac
        done < <(jq -r '.plugin[]? | if type == "array" then .[0] else . end' "$global_config")
      else
        warn "no writable global config yet (created when plugins/settings are added)"
      fi

      if [ -e "$plugin_manifest" ]; then
        plugin_api_version=$(jq -r '.dependencies["@opencode-ai/plugin"] // empty' "$plugin_manifest")
        normalized_plugin_api_version=''${plugin_api_version#^}
        normalized_plugin_api_version=''${normalized_plugin_api_version#~}
        if [ -z "$plugin_api_version" ]; then
          warn "plugin manifest does not pin @opencode-ai/plugin"
        elif [ "$normalized_plugin_api_version" = "$(opencode --version)" ]; then
          pass "plugin API matches the OpenCode version"
        else
          warn "plugin API $plugin_api_version differs from OpenCode $(opencode --version)"
        fi
      else
        warn "no plugin package manifest present"
      fi

      if [ -e "$theme_config" ] && jq -e '.theme.background.dark | type == "string"' "$theme_config" >/dev/null; then
        pass "Stylix theme is present"
      else
        fail "Stylix theme is missing or malformed: $theme_config"
      fi

      if timeout 10s env OPENCODE_CONFIG="$managed_config" opencode --pure debug config >/dev/null 2>&1; then
        pass "OpenCode resolves the layered configuration"
      else
        fail "OpenCode could not resolve the layered configuration"
      fi

      for server in ${lib.escapeShellArgs managedMcpNames}; do
        if jq -e --arg server "$server" '.mcp[$server].enabled == true' "$managed_config" >/dev/null; then
          pass "MCP configured: $server"
        else
          fail "MCP missing or disabled: $server"
        fi
      done

      ${lib.optionalString cfg.integrations.jcodemunch.enable ''
        if [ -e "$jcodemunch_config" ] && jq -e '
          .tool_profile == "core" and
          .compact_schemas == true and
          .share_savings == false and
          .use_ai_summaries == false
        ' "$jcodemunch_config" >/dev/null; then
          pass "jCodeMunch privacy and compact-profile config is active"
        else
          fail "jCodeMunch managed config is missing or incorrect"
        fi
      ''}

      ${lib.optionalString cfg.integrations.codex.enable ''
        if jq -e --arg model ${lib.escapeShellArg cfg.integrations.codex.model} '.model == $model' "$managed_config" >/dev/null; then
          pass "default model is ${cfg.integrations.codex.model}"
        else
          fail "default model is not ${cfg.integrations.codex.model}"
        fi

        if [ -e "$auth_file" ] && jq -e 'has("openai")' "$auth_file" >/dev/null 2>&1; then
          pass "native OpenAI authentication is configured"
        else
          warn "native OpenAI authentication missing; run: opencode auth login"
        fi

        if [ -e "$model_cache" ] && jq -e '.openai.models["gpt-5.6-sol"] != null' "$model_cache" >/dev/null 2>&1; then
          pass "OpenCode catalog contains GPT-5.6 Sol"
        else
          warn "GPT-5.6 Sol is not present in the local model cache yet"
        fi
      ''}

      for tool in ${lib.escapeShellArgs extraPackageExecutables}; do
        if command -v "$tool" >/dev/null; then
          pass "tool available: $tool"
        else
          fail "tool missing from OpenCode PATH: $tool"
        fi
      done

      if [ "$failures" -ne 0 ]; then
        printf '\n%d check(s) failed.\n' "$failures"
        exit 1
      fi

      printf '\nAll checks passed.\n'
    '';
  };
in
{
  inherit
    cfg
    defaultTuiSettings
    hasRetrievalIntegrations
    integrationPackages
    jcodemunchConfig
    jsonFormat
    opencodeDoctor
    opencodeExtraPackages
    opencodeIntegrationsSync
    validatedManagedSettings
    ;
}
