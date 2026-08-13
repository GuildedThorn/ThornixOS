{
  # TypeScript/JavaScript LSP, formatting, tests, code actions, and debugging.
  # Kill-switch: thorn.programs.nixvim.typescript.enable = false.
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.nixvim;
    in
    {
      options.thorn.programs.nixvim.typescript.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nixvim TypeScript and JavaScript development stack.";
      };

      config = lib.mkIf (cfg.enable && cfg.typescript.enable) {
        programs.nixvim = lib.mkMerge [
          (lib.mkIf cfg.lsp.enable {
            extraPlugins = [ pkgs.vimPlugins.nvim-vtsls ];

            plugins = {
              lsp.servers = {
                # vtsls exposes the VS Code TypeScript feature set. Do not
                # enable ts_ls alongside it: both would attach to every JS/TS
                # buffer and duplicate completion, diagnostics, and actions.
                vtsls = {
                  enable = true;
                  settings = {
                    vtsls = {
                      autoUseWorkspaceTsdk = true;
                      enableMoveToFileCodeAction = true;
                      experimental.completion.enableServerSideFuzzyMatch = true;
                    };

                    typescript = {
                      updateImportsOnFileMove = "always";
                      suggest.completeFunctionCalls = true;
                      preferences = {
                        importModuleSpecifier = "shortest";
                        includePackageJsonAutoImports = "auto";
                      };
                      inlayHints = {
                        enumMemberValues.enabled = true;
                        functionLikeReturnTypes.enabled = true;
                        parameterNames.enabled = "literals";
                        parameterTypes.enabled = true;
                        propertyDeclarationTypes.enabled = true;
                        variableTypes.enabled = false;
                      };
                    };

                    javascript = {
                      updateImportsOnFileMove = "always";
                      suggest.completeFunctionCalls = true;
                      inlayHints = {
                        enumMemberValues.enabled = true;
                        functionLikeReturnTypes.enabled = true;
                        parameterNames.enabled = "literals";
                        parameterTypes.enabled = true;
                        propertyDeclarationTypes.enabled = true;
                        variableTypes.enabled = false;
                      };
                    };
                  };
                };

                eslint = {
                  enable = true;
                  settings = {
                    format = false;
                    workingDirectory.mode = "auto";
                  };
                };
              };

              conform-nvim.settings.formatters_by_ft = {
                javascript = [ "prettier" ];
                javascriptreact = [ "prettier" ];
                typescript = [ "prettier" ];
                typescriptreact = [ "prettier" ];
              };
            };

            extraConfigLua = ''
              require("vtsls").config({
                refactor_auto_rename = true,
              })

              vim.api.nvim_create_autocmd("LspAttach", {
                callback = function(args)
                  local client = vim.lsp.get_client_by_id(args.data.client_id)
                  if not client or client.name ~= "vtsls" then
                    return
                  end

                  local commands = require("vtsls").commands
                  local function map(lhs, rhs, desc)
                    vim.keymap.set("n", lhs, rhs, {
                      buffer = args.buf,
                      silent = true,
                      desc = desc,
                    })
                  end

                  map("<leader>co", function()
                    commands.organize_imports(args.buf)
                  end, "Organize imports")
                  map("<leader>cM", function()
                    commands.add_missing_imports(args.buf)
                  end, "Add missing imports")
                  map("<leader>cu", function()
                    commands.remove_unused_imports(args.buf)
                  end, "Remove unused imports")
                  map("<leader>cD", function()
                    commands.goto_source_definition(0)
                  end, "Go to source definition")
                  map("<leader>cF", function()
                    commands.file_references(args.buf)
                  end, "Find file references")
                  map("<leader>cR", function()
                    commands.rename_file(args.buf)
                  end, "Rename file")
                  map("<leader>cV", function()
                    commands.select_ts_version(args.buf)
                  end, "Select TypeScript version")
                end,
                desc = "TypeScript buffer actions",
              })
            '';
          })

          (lib.mkIf cfg.testing.enable {
            plugins.neotest.adapters = {
              jest.enable = true;
              vitest.enable = true;
            };
          })

          (lib.mkIf cfg.debug.enable {
            extraConfigLua = ''
              local dap = require("dap")

              dap.adapters["pwa-node"] = {
                type = "server",
                host = "localhost",
                port = "''${port}",
                executable = {
                  command = "${pkgs.vscode-js-debug}/bin/js-debug",
                  args = { "''${port}" },
                },
              }

              local js_config = {
                {
                  type = "pwa-node",
                  request = "launch",
                  name = "Launch current file",
                  program = "''${file}",
                  cwd = "''${workspaceFolder}",
                  sourceMaps = true,
                  skipFiles = {
                    "<node_internals>/**",
                    "**/node_modules/**",
                  },
                  resolveSourceMapLocations = {
                    "''${workspaceFolder}/**",
                    "!**/node_modules/**",
                  },
                },
                {
                  type = "pwa-node",
                  request = "attach",
                  name = "Attach to Node process",
                  processId = require("dap.utils").pick_process,
                  cwd = "''${workspaceFolder}",
                  sourceMaps = true,
                  skipFiles = {
                    "<node_internals>/**",
                    "**/node_modules/**",
                  },
                },
              }

              dap.configurations.javascript = js_config
              dap.configurations.javascriptreact = js_config
              dap.configurations.typescript = js_config
              dap.configurations.typescriptreact = js_config
            '';
          })
        ];
      };
    };
}
