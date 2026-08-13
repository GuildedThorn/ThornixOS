{
  # C#/.NET language intelligence, formatting, project workflows, tests, and
  # debugging. Everything is Nix-managed and reproducible; easy-dotnet.nvim is
  # intentionally omitted because its current server is a mutable global tool.
  # Kill-switch: thorn.programs.nixvim.dotnet.enable = false.
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.nixvim;
      dotnetSdk = pkgs.dotnetCorePackages.combinePackages [
        pkgs.dotnetCorePackages.sdk_10_0
        pkgs.dotnetCorePackages.sdk_9_0
        pkgs.dotnetCorePackages.sdk_8_0
      ];
    in
    {
      options.thorn.programs.nixvim.dotnet.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nixvim C# and .NET development stack.";
      };

      config = lib.mkIf (cfg.enable && cfg.dotnet.enable) {
        programs.nixvim = lib.mkMerge [
          {
            extraPackages =
              with pkgs;
              [
                csharpier
                libxml2
                netcoredbg
              ]
              ++ [ dotnetSdk ];

            filetype.extension = {
              cshtml = "razor";
              razor = "razor";
              csproj = "xml";
              fsproj = "xml";
              props = "xml";
              slnx = "xml";
              targets = "xml";
              vbproj = "xml";
            };

            keymaps = [
              {
                mode = "n";
                key = "<leader>nb";
                action = "<cmd>DotnetBuild<CR>";
                options = {
                  desc = ".NET: Build";
                  silent = true;
                };
              }
              {
                mode = "n";
                key = "<leader>nc";
                action = "<cmd>DotnetClean<CR>";
                options = {
                  desc = ".NET: Clean";
                  silent = true;
                };
              }
              {
                mode = "n";
                key = "<leader>nr";
                action = "<cmd>DotnetRun<CR>";
                options = {
                  desc = ".NET: Run";
                  silent = true;
                };
              }
              {
                mode = "n";
                key = "<leader>nR";
                action = "<cmd>DotnetRestore<CR>";
                options = {
                  desc = ".NET: Restore";
                  silent = true;
                };
              }
              {
                mode = "n";
                key = "<leader>nn";
                action = "<cmd>DotnetUI new_item<CR>";
                options = {
                  desc = ".NET: New Item";
                  silent = true;
                };
              }
              {
                mode = "n";
                key = "<leader>np";
                action = "<cmd>DotnetUI project package add<CR>";
                options = {
                  desc = ".NET: Add Package";
                  silent = true;
                };
              }
              {
                mode = "n";
                key = "<leader>nP";
                action = "<cmd>DotnetUI project package remove<CR>";
                options = {
                  desc = ".NET: Remove Package";
                  silent = true;
                };
              }
              {
                mode = "n";
                key = "<leader>na";
                action = "<cmd>DotnetUI project reference add<CR>";
                options = {
                  desc = ".NET: Add Project Reference";
                  silent = true;
                };
              }
              {
                mode = "n";
                key = "<leader>nd";
                action = "<cmd>DotnetUI project reference remove<CR>";
                options = {
                  desc = ".NET: Remove Project Reference";
                  silent = true;
                };
              }
            ];

            plugins = {
              dotnet = {
                enable = true;
                settings = {
                  # Creating an empty file should not silently write a class.
                  bootstrap.auto_bootstrap = false;
                  project_selection.path_display = "filename_first";
                };
              };

              which-key.settings.spec = [
                {
                  __unkeyed-1 = "<leader>n";
                  group = ".NET";
                }
              ];
            };

            extraConfigLua = ''
              local function dotnet_terminal(action)
                require("toggleterm").exec(
                  "dotnet " .. action,
                  nil,
                  15,
                  nil,
                  "horizontal"
                )
              end

              vim.api.nvim_create_user_command("DotnetBuild", function()
                dotnet_terminal("build")
              end, { desc = "Build the current .NET workspace" })
              vim.api.nvim_create_user_command("DotnetClean", function()
                dotnet_terminal("clean")
              end, { desc = "Clean the current .NET workspace" })
              vim.api.nvim_create_user_command("DotnetRun", function()
                dotnet_terminal("run")
              end, { desc = "Run the current .NET project" })
              vim.api.nvim_create_user_command("DotnetRestore", function()
                dotnet_terminal("restore")
              end, { desc = "Restore the current .NET workspace" })
            '';
          }

          (lib.mkIf cfg.lsp.enable {
            plugins = {
              roslyn = {
                enable = true;
                settings = {
                  broad_search = true;
                  filewatching = "roslyn";
                  lock_target = false;
                };
              };

              # MSBuild project files are XML even though their extensions are
              # project-specific.
              lsp.servers.lemminx.enable = true;

              conform-nvim.settings.formatters_by_ft = {
                cs = [ "csharpier" ];
                xml = [ "xmllint" ];
              };
            };

            extraConfigLua = ''
              vim.lsp.config("roslyn", {
                settings = {
                  ["csharp|background_analysis"] = {
                    dotnet_analyzer_diagnostics_scope = "fullSolution",
                    dotnet_compiler_diagnostics_scope = "fullSolution",
                  },
                  ["csharp|code_lens"] = {
                    dotnet_enable_references_code_lens = true,
                    dotnet_enable_tests_code_lens = true,
                  },
                  ["csharp|completion"] = {
                    dotnet_provide_regex_completions = true,
                    dotnet_show_completion_items_from_unimported_namespaces = true,
                    dotnet_show_name_completion_suggestions = true,
                  },
                  ["csharp|formatting"] = {
                    dotnet_organize_imports_on_format = true,
                  },
                  ["csharp|inlay_hints"] = {
                    csharp_enable_inlay_hints_for_implicit_object_creation = true,
                    csharp_enable_inlay_hints_for_implicit_variable_types = true,
                    csharp_enable_inlay_hints_for_lambda_parameter_types = true,
                    csharp_enable_inlay_hints_for_types = true,
                    dotnet_enable_inlay_hints_for_indexer_parameters = true,
                    dotnet_enable_inlay_hints_for_literal_parameters = true,
                    dotnet_enable_inlay_hints_for_object_creation_parameters = true,
                    dotnet_enable_inlay_hints_for_other_parameters = false,
                    dotnet_enable_inlay_hints_for_parameters = true,
                    dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
                    dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
                    dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
                  },
                  ["csharp|symbol_search"] = {
                    dotnet_search_reference_assemblies = true,
                  },
                },
              })

              vim.api.nvim_create_autocmd("LspAttach", {
                callback = function(args)
                  local client = vim.lsp.get_client_by_id(args.data.client_id)
                  if not client or client.name ~= "roslyn" then
                    return
                  end

                  local function map(lhs, rhs, desc)
                    vim.keymap.set("n", lhs, rhs, {
                      buffer = args.buf,
                      silent = true,
                      desc = desc,
                    })
                  end

                  map("<leader>cc", vim.lsp.codelens.run, "Run CodeLens")
                  map("<leader>cT", "<cmd>Roslyn target<CR>", "Select Roslyn target")

                  vim.lsp.codelens.enable(true, { bufnr = args.buf })
                end,
                desc = "C# buffer actions",
              })
            '';
          })

          (lib.mkIf cfg.testing.enable {
            plugins.neotest.adapters.dotnet = {
              enable = true;
              settings = {
                dap = {
                  adapter_name = "coreclr";
                  args.justMyCode = true;
                };
                discovery_root = "project";
              };
            };
          })

          (lib.mkIf cfg.debug.enable {
            extraConfigLua = ''
              local dap = require("dap")

              dap.adapters.coreclr = {
                type = "executable",
                command = "${pkgs.netcoredbg}/bin/netcoredbg",
                args = { "--interpreter=vscode" },
              }

              local function current_project_dll()
                local buffer_path = vim.api.nvim_buf_get_name(0)
                local start_path = vim.fs.dirname(buffer_path)
                local project = vim.fs.find(function(name)
                  return name:match("%.csproj$") ~= nil
                end, {
                  path = start_path,
                  upward = true,
                  type = "file",
                })[1]

                if project then
                  local project_dir = vim.fs.dirname(project)
                  local assembly = vim.fn.fnamemodify(project, ":t:r")
                  local candidates = vim.fn.glob(
                    project_dir .. "/bin/Debug/*/" .. assembly .. ".dll",
                    false,
                    true
                  )
                  table.sort(candidates, function(left, right)
                    return vim.fn.getftime(left) > vim.fn.getftime(right)
                  end)
                  if candidates[1] then
                    return candidates[1]
                  end
                end

                local default = project
                    and (vim.fs.dirname(project) .. "/bin/Debug/")
                  or (vim.fn.getcwd() .. "/bin/Debug/")
                return vim.fn.input("Path to .NET assembly: ", default, "file")
              end

              dap.configurations.cs = {
                {
                  type = "coreclr",
                  name = "Launch current project",
                  request = "launch",
                  program = current_project_dll,
                  cwd = "''${workspaceFolder}",
                  justMyCode = true,
                  stopAtEntry = false,
                },
                {
                  type = "coreclr",
                  name = "Attach to .NET process",
                  request = "attach",
                  processId = require("dap.utils").pick_process,
                  cwd = "''${workspaceFolder}",
                  justMyCode = true,
                },
              }
            '';
          })
        ];
      };
    };
}
