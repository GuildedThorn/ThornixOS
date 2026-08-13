{
  # Shared test runner UI and conventional test keymaps. Language modules add
  # their own adapters so disabling one stack does not affect the others.
  # Kill-switch: thorn.programs.nixvim.testing.enable = false.
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.nixvim;
    in
    {
      options.thorn.programs.nixvim.testing.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nixvim test runner and shared test keymaps.";
      };

      config = lib.mkIf (cfg.enable && cfg.testing.enable) {
        programs.nixvim = {
          keymaps = [
            {
              mode = "n";
              key = "<leader>tt";
              action.__raw = "function() require('neotest').run.run(vim.fn.expand('%')) end";
              options = {
                desc = "Test: Run File";
                silent = true;
              };
            }
            {
              mode = "n";
              key = "<leader>tT";
              action.__raw = "function() require('neotest').run.run(vim.uv.cwd()) end";
              options = {
                desc = "Test: Run All";
                silent = true;
              };
            }
            {
              mode = "n";
              key = "<leader>tr";
              action.__raw = "function() require('neotest').run.run() end";
              options = {
                desc = "Test: Run Nearest";
                silent = true;
              };
            }
            {
              mode = "n";
              key = "<leader>tl";
              action.__raw = "function() require('neotest').run.run_last() end";
              options = {
                desc = "Test: Run Last";
                silent = true;
              };
            }
            {
              mode = "n";
              key = "<leader>td";
              action.__raw = "function() require('neotest').run.run({ strategy = 'dap' }) end";
              options = {
                desc = "Test: Debug Nearest";
                silent = true;
              };
            }
            {
              mode = "n";
              key = "<leader>ts";
              action.__raw = "function() require('neotest').summary.toggle() end";
              options = {
                desc = "Test: Toggle Summary";
                silent = true;
              };
            }
            {
              mode = "n";
              key = "<leader>to";
              action.__raw = "function() require('neotest').output.open({ enter = true, auto_close = true }) end";
              options = {
                desc = "Test: Show Output";
                silent = true;
              };
            }
            {
              mode = "n";
              key = "<leader>tO";
              action.__raw = "function() require('neotest').output_panel.toggle() end";
              options = {
                desc = "Test: Toggle Output Panel";
                silent = true;
              };
            }
            {
              mode = "n";
              key = "<leader>tS";
              action.__raw = "function() require('neotest').run.stop() end";
              options = {
                desc = "Test: Stop";
                silent = true;
              };
            }
          ];

          plugins = {
            neotest = {
              enable = true;
              settings = {
                output.open_on_run = false;
                output_panel.open = "botright split | resize 15";
                quickfix.open = false;
                status.virtual_text = true;
                summary.animated = true;
              };
            };

            which-key.settings.spec = [
              {
                __unkeyed-1 = "<leader>t";
                group = "Tests";
              }
            ];
          };
        };
      };
    };
}
