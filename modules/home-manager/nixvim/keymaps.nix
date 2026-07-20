{
  # General keymaps (clipboard, telescope, yazi, buffers, neogit). Debug
  # keymaps live with the rest of the DAP setup in debug.nix; LSP buffer
  # keymaps attach via autocmd in lsp.nix.
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
      options.thorn.programs.nixvim.keymaps.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "General nixvim keymaps.";
      };

      config = lib.mkIf (cfg.enable && cfg.keymaps.enable) {
        programs.nixvim.keymaps = [

          {
            mode = "n";
            key = "<leader>yy";
            action = "\"+yy";
            options.desc = "Copy current line";
          }

          {
            mode = "n";
            key = "<leader>ya";
            action = "\"+ggyG";
            options.desc = "Copy entire file";
          }

          {
            mode = [
              "n"
              "v"
            ];
            key = "<leader>p";
            action = "\"+p";
            options.desc = "Paste from clipboard";
          }

          {
            mode = "n";
            key = "<leader>-";
            action = "<cmd>Yazi<CR>";
            options = {
              desc = "Open Yazi at current file";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>=";
            action = "<cmd>Yazi cwd<CR>";
            options = {
              desc = "Open Yazi in cwd";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>ff";
            action = "<cmd>Telescope find_files<CR>";
            options = {
              desc = "Find Files";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>fg";
            action = "<cmd>Telescope live_grep<CR>";
            options = {
              desc = "Live Grep";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>lg";
            action = "<cmd>Neogit<CR>";
            options = {
              desc = "Neogit UI";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>fb";
            action = "<cmd>Telescope buffers<CR>";
            options = {
              desc = "Find Buffers";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<S-h>";
            action = "<cmd>BufferPrevious<CR>";
          }

          {
            mode = "n";
            key = "<S-l>";
            action = "<cmd>BufferNext<CR>";
          }

          {
            mode = "n";
            key = "<leader>x";
            action = "<Cmd>BufferClose<CR>";
          }

          {
            mode = "n";
            key = "<leader>fp";
            action = "<cmd>Telescope projects<CR>";
            options = {
              desc = "Find Projects";
              silent = true;
            };
          }
        ];
      };
    };
}
