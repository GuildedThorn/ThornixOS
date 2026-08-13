{
  # Shared DAP core, UI listeners, non-language-specific adapters, and the
  # <leader>d keymaps. TypeScript and C# adapters live with their language
  # stacks so their kill-switches remove the whole integration.
  # Kill-switch: thorn.programs.nixvim.debug.enable = false.
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
      options.thorn.programs.nixvim.debug.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nixvim debugging (DAP) setup.";
      };

      config = lib.mkIf (cfg.enable && cfg.debug.enable) {
        programs.nixvim = {
          keymaps = [
            {
              mode = "n";
              key = "<leader>dc";
              action.__raw = "function() require('dap').continue() end";
              options = {
                desc = "Debug: Continue";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>do";
              action.__raw = "function() require('dap').step_out() end";
              options = {
                desc = "Debug: Step Out";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>di";
              action.__raw = "function() require('dap').step_into() end";
              options = {
                desc = "Debug: Step Into";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>dO";
              action.__raw = "function() require('dap').step_over() end";
              options = {
                desc = "Debug: Step Over";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>db";
              action.__raw = "function() require('dap').toggle_breakpoint() end";
              options = {
                desc = "Debug: Toggle Breakpoint";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>dB";
              action.__raw = "function() require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: ')) end";
              options = {
                desc = "Debug: Conditional Breakpoint";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>dr";
              action.__raw = "function() require('dap').repl.toggle() end";
              options = {
                desc = "Debug: Toggle REPL";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>dt";
              action.__raw = "function() require('dap').terminate() end";
              options = {
                desc = "Debug: Terminate";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>du";
              action.__raw = "function() require('dapui').toggle() end";
              options = {
                desc = "Debug: Toggle UI";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<leader>dl";
              action.__raw = "function() require('dap').run_last() end";
              options = {
                desc = "Debug: Run Last";
                silent = true;
              };
            }

            # Familiar IDE function keys, in addition to the discoverable
            # <leader>d mappings above.
            {
              mode = "n";
              key = "<F5>";
              action.__raw = "function() require('dap').continue() end";
              options = {
                desc = "Debug: Continue";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<F9>";
              action.__raw = "function() require('dap').toggle_breakpoint() end";
              options = {
                desc = "Debug: Toggle Breakpoint";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<F10>";
              action.__raw = "function() require('dap').step_over() end";
              options = {
                desc = "Debug: Step Over";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<F11>";
              action.__raw = "function() require('dap').step_into() end";
              options = {
                desc = "Debug: Step Into";
                silent = true;
              };
            }

            {
              mode = "n";
              key = "<S-F11>";
              action.__raw = "function() require('dap').step_out() end";
              options = {
                desc = "Debug: Step Out";
                silent = true;
              };
            }
          ];

          extraConfigLua = ''
            -- Open/close the DAP UI automatically around debug sessions
            local dap, dapui = require("dap"), require("dapui")
            dap.listeners.after.event_initialized["dapui_config"] = function()
              dapui.open()
            end
            dap.listeners.before.event_terminated["dapui_config"] = function()
              dapui.close()
            end
            dap.listeners.before.event_exited["dapui_config"] = function()
              dapui.close()
            end

            -- C#: netcoredbg
            dap.adapters.coreclr = {
              type = "executable",
              command = "${pkgs.netcoredbg}/bin/netcoredbg",
              args = { "--interpreter=vscode" },
            }
            dap.configurations.cs = {
              {
                type = "coreclr",
                name = "Launch - netcoredbg",
                request = "launch",
                program = function()
                  return vim.fn.input("Path to dll: ", vim.fn.getcwd() .. "/bin/Debug/", "file")
                end,
              },
            }
          '';

          plugins = {
            dap.enable = true;
            dap-ui.enable = true;
            dap-virtual-text.enable = true;

            # Python: auto-installs debugpy, no manual adapter wiring needed
            dap-python.enable = true;

            # C / C++ / Rust via codelldb (bundled by the vscode-lldb extension)
            dap-lldb = {
              enable = true;
              settings.codelldb_path = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
            };
          };
        };
      };
    };
}
