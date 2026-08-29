{ inputs, ... }:
{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      runtime = import ../../lib/opencode-runtime.nix {
        inherit
          config
          inputs
          lib
          pkgs
          ;
      };
      inherit (runtime)
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
    in
    {
      options.thorn.programs.opencode = {
        enable = lib.mkEnableOption "Thorn's OpenCode Home Manager configuration";

        package = lib.mkPackageOption pkgs "opencode" { };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [
            bat
            deadnix
            fd
            gh
            git
            jq
            nixd
            nixfmt
            ripgrep
            shellcheck
            shfmt
            statix
            tree
          ];
          description = "Reproducible command-line toolchain exposed to OpenCode.";
        };

        integrations = {
          mcpTimeout = lib.mkOption {
            type = lib.types.ints.positive;
            default = 120000;
            description = ''
              Timeout in milliseconds for local MCP requests. The generous
              default also covers first-run hydration of locked uv tools.
            '';
          };

          jcodemunch.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Enable the locked jCodeMunch MCP server with its compact core
              tool profile and usage telemetry disabled. Upstream permits
              personal/non-commercial use; commercial use requires a license.
            '';
          };

          jcodemunch.trustedFolders = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "${config.home.homeDirectory}/Documents" ];
            description = ''
              Directory roots jCodeMunch may index. Its secure whitelist mode
              remains enabled so an MCP call cannot crawl arbitrary home data.
            '';
          };

          serena.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Enable the locked Serena semantic-code MCP server in its IDE
              context, which suppresses tools that overlap with OpenCode.
            '';
          };

          context7 = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable the Context7 documentation MCP server.";
            };

            package = lib.mkPackageOption pkgs "context7-mcp" { };
          };

          graphify.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Install the locked Graphify CLI plus an OpenCode skill, command,
              and graph-aware reminder plugin. Graphs remain per-project and
              are never generated during Home Manager activation.
            '';
          };

          freecad.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Enable the pinned FreeCAD MCP bridge. FreeCAD must be running
              with its loopback RPC addon enabled before tools can control it.
            '';
          };

          codex = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Use OpenCode's native OpenAI OAuth provider and GPT-5.6 Codex
                model family instead of a third-party authentication plugin.
              '';
            };

            model = lib.mkOption {
              type = lib.types.str;
              default = "openai/gpt-5.6-sol";
              description = "Default OpenAI Codex model used by OpenCode.";
            };

            smallModel = lib.mkOption {
              type = lib.types.str;
              default = "openai/gpt-5.6-terra";
              description = "Lower-cost GPT-5.6 model used for small background tasks.";
            };
          };
        };

        managedSettings = lib.mkOption {
          inherit (jsonFormat) type;
          default = { };
          example = {
            share = "manual";
            subagent_depth = 1;
          };
          description = ''
            Extra Nix-managed OpenCode settings recursively merged over the
            privacy and reliability defaults. This is loaded through
            OPENCODE_CONFIG so the plugin-managed global opencode.json remains
            writable. Plugins belong in the global config, not this overlay.
          '';
        };

        tuiSettings = lib.mkOption {
          inherit (jsonFormat) type;
          default = { };
          example = {
            scroll_speed = 5;
            attention.notifications = false;
          };
          description = ''
            Extra TUI settings recursively merged over Thorn's defaults.
            The theme is owned by the Stylix OpenCode target.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = !(cfg.managedSettings ? plugin);
            message = "thorn.programs.opencode.managedSettings.plugin would make plugin updates immutable; keep plugins in the writable global opencode.json";
          }
          {
            assertion = !(cfg.tuiSettings ? theme);
            message = "thorn.programs.opencode.tuiSettings.theme conflicts with the Stylix-owned OpenCode theme";
          }
          {
            assertion =
              !cfg.integrations.codex.enable
              || (
                lib.hasPrefix "openai/" cfg.integrations.codex.model
                && lib.hasPrefix "openai/" cfg.integrations.codex.smallModel
              );
            message = "thorn.programs.opencode.integrations.codex models must use OpenCode's openai/ provider";
          }
        ];

        programs.opencode = {
          enable = true;
          inherit (cfg) package;
          extraPackages = opencodeExtraPackages;
          enableMcpIntegration = true;
          tui = lib.recursiveUpdate defaultTuiSettings cfg.tuiSettings;

          agents.thornix-auditor = ''
            ---
            description: Audit NixOS and Home Manager changes without modifying files
            mode: subagent
            temperature: 0.1
            permission:
              edit: deny
              bash: ask
              task: deny
            ---

            Audit NixOS and Home Manager changes in the current repository.
            Read the repository instructions before judging the change. Determine
            every affected host, inspect option types and module merge behavior,
            and look for evaluation failures, secret exposure, activation hazards,
            and unintended changes to mutable state.

            Do not modify files. Return findings ordered by severity with precise
            file and line references, followed by the smallest sufficient set of
            validation commands.
          '';

          commands = {
            thornix-audit = ''
              ---
              description: Run a read-only NixOS and Home Manager audit
              agent: thornix-auditor
              ---

              Audit the current working tree. Pay special attention to: $ARGUMENTS
            '';

            thornix-check = ''
              ---
              description: Format, evaluate, and build every affected Thornix host
              ---

              Validate the current ThornixOS working tree end to end.

              1. Read CLAUDE.md and preserve unrelated dirty changes.
              2. Determine which hosts are affected by the diff.
              3. Run nixfmt only on changed Nix files, then git diff --check.
              4. Run nix flake check with import-from-derivation enabled when required.
              5. Build each affected NixOS toplevel with --no-link.
              6. Report exact commands, results, and any unverified risk.

              Never switch generations or mutate the running system.
              Additional focus: $ARGUMENTS
            '';
          }
          // lib.optionalAttrs cfg.integrations.graphify.enable {
            graphify = ''
              ---
              description: Build, update, or query a local Graphify knowledge graph
              ---

              Use the `graphify` skill. Work only in the current project; do
              not run Graphify's installer because Home Manager already owns
              the OpenCode integration. Target or question: $ARGUMENTS
            '';
          };

          skills = lib.optionalAttrs cfg.integrations.graphify.enable {
            graphify = ''
              ---
              name: graphify
              description: Map or query cross-file architecture with Graphify's local knowledge graph
              ---

              # Graphify

              Use this for architecture, dependency paths, blast radius, and
              questions spanning several files. For a tiny lookup, use the
              ordinary code tools instead.

              1. Check for `graphify-out/graph.json` in the project root.
              2. If it exists, query before broad file searching:
                 - `graphify query "question"`
                 - `graphify path "source" "target"`
                 - `graphify explain "symbol"`
              3. If the user asks to create a graph, run
                 `graphify extract . --code-only`. This is local tree-sitter
                 analysis and does not require an LLM or API key.
              4. After material code changes, refresh an existing graph with
                 `graphify update .`; do not create one unsolicited.
              5. Treat graph output as an index, then verify decisive claims
                 against source before editing.

              Never run `graphify install` or `graphify opencode install`;
              Home Manager owns the skill and plugin.
            '';
          };
        };

        stylix.targets.opencode.enable = true;

        xdg.configFile = {
          "opencode/nix-managed.json".source = validatedManagedSettings;

          "opencode/instructions/retrieval.md" = lib.mkIf hasRetrievalIntegrations {
            text = ''
              # Retrieval policy

              Use the narrowest structural source that answers the question;
              do not call multiple overlapping retrieval systems by default.

              ${lib.optionalString cfg.integrations.jcodemunch.enable ''
                - Call `jcodemunch_guide` before first use in a session. Prefer
                  jCodeMunch symbol, reference, hierarchy, and blast-radius
                  tools over reading whole files. Its core profile can expose
                  another tier through the guide when genuinely necessary.
              ''}
              ${lib.optionalString cfg.integrations.serena.enable ''
                - Use Serena for language-server-backed symbol navigation,
                  references, and semantic refactors. The `ide` context omits
                  basic file and shell tools already supplied by OpenCode.
              ''}
              ${lib.optionalString cfg.integrations.context7.enable ''
                - Use Context7 for current library and API documentation:
                  resolve the library identifier, then query only the needed
                  topic. Do not use it for facts already present in the repo.
              ''}
              ${lib.optionalString cfg.integrations.graphify.enable ''
                - When `graphify-out/graph.json` exists, use `graphify query`,
                  `path`, or `explain` before broad grep for architectural and
                  cross-file questions. Verify decisive graph claims in source.
              ''}
            '';
          };

          "opencode/plugins/nix-graphify.js" = lib.mkIf cfg.integrations.graphify.enable {
            text = ''
              // Nix-managed Graphify reminder plugin. The Graphify CLI and
              // skill are managed separately; no project config is rewritten.
              import { existsSync } from "fs";
              import { join } from "path";

              export const NixGraphifyPlugin = async ({ directory }) => {
                let reminded = false;

                return {
                  "tool.execute.before": async (input, output) => {
                    if (reminded) return;
                    if (!existsSync(join(directory, "graphify-out", "graph.json"))) return;

                    if (input.tool === "bash") {
                      output.args.command =
                        'echo "[graphify] graph available. Query it before broad grep for cross-file questions." ; ' +
                        output.args.command;
                      reminded = true;
                    }
                  },
                };
              };
            '';
          };
        };

        home = {
          file.".code-index/config.jsonc" = lib.mkIf cfg.integrations.jcodemunch.enable {
            source = jcodemunchConfig;
          };

          packages = lib.unique (
            [
              opencodeDoctor
              opencodeIntegrationsSync
            ]
            ++ integrationPackages
          );

          sessionVariables = {
            OPENCODE_CONFIG = "${config.xdg.configHome}/opencode/nix-managed.json";
            OPENCODE_DISABLE_AUTOUPDATE = "true";
          };
        };

        programs.zsh.shellAliases = {
          oc = "opencode";
          ocauth = "opencode auth login";
          ocd = "opencode-doctor";
          ocmcp = "opencode mcp list";
          ocmodels = "opencode models openai";
          ocplug = "opencode plugin --global";
          ocpure = "opencode --pure";
          ocsync = "opencode-integrations-sync";
          ocstats = "opencode stats --days 30 --models 10 --tools 10";
        };
      };
    };
}
