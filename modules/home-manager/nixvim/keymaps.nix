{
  # General keymaps. Debug keymaps live with DAP in debug.nix; LSP buffer
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
            key = "<Esc>";
            action = "<cmd>nohlsearch<CR>";
            options = {
              desc = "Clear search highlight";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<C-s>";
            action = "<cmd>update<CR>";
            options = {
              desc = "Save file";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>qq";
            action = "<cmd>qa<CR>";
            options = {
              desc = "Quit all";
              silent = true;
            };
          }

          {
            mode = [
              "n"
              "v"
            ];
            key = "<leader>y";
            action = "\"+y";
            options = {
              desc = "Yank to system clipboard";
            };
          }

          {
            mode = "n";
            key = "<leader>Y";
            action = "\"+Y";
            options.desc = "Yank line to system clipboard";
          }

          {
            mode = "n";
            key = "<leader>ya";
            action = "ggVG\"+y";
            options.desc = "Yank entire file to system clipboard";
          }

          {
            mode = [
              "n"
              "v"
            ];
            key = "<leader>p";
            action = "\"+p";
            options.desc = "Paste from system clipboard";
          }

          {
            mode = [
              "n"
              "v"
            ];
            key = "<leader>e";
            action = "<cmd>Yazi<CR>";
            options = {
              desc = "File explorer";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>E";
            action = "<cmd>Yazi cwd<CR>";
            options = {
              desc = "File explorer in cwd";
              silent = true;
            };
          }

          # Search
          {
            mode = "n";
            key = "<leader>ff";
            action = "<cmd>Telescope find_files<CR>";
            options = {
              desc = "Find files";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>fg";
            action = "<cmd>Telescope live_grep<CR>";
            options = {
              desc = "Grep text";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>fb";
            action = "<cmd>Telescope buffers<CR>";
            options = {
              desc = "Find buffers";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>fr";
            action = "<cmd>Telescope oldfiles<CR>";
            options = {
              desc = "Recent files";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>fh";
            action = "<cmd>Telescope help_tags<CR>";
            options = {
              desc = "Help tags";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>fk";
            action = "<cmd>Telescope keymaps<CR>";
            options = {
              desc = "Find keymaps";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>fp";
            action = "<cmd>Telescope projects<CR>";
            options = {
              desc = "Find projects";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>/";
            action = "<cmd>Telescope current_buffer_fuzzy_find<CR>";
            options = {
              desc = "Search current buffer";
              silent = true;
            };
          }

          # Git
          {
            mode = "n";
            key = "<leader>gg";
            action = "<cmd>Neogit<CR>";
            options = {
              desc = "Neogit";
              silent = true;
            };
          }

          # Buffers
          {
            mode = "n";
            key = "<S-h>";
            action = "<cmd>BufferPrevious<CR>";
            options = {
              desc = "Previous buffer";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<S-l>";
            action = "<cmd>BufferNext<CR>";
            options = {
              desc = "Next buffer";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "[b";
            action = "<cmd>BufferPrevious<CR>";
            options = {
              desc = "Previous buffer";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "]b";
            action = "<cmd>BufferNext<CR>";
            options = {
              desc = "Next buffer";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>bd";
            action = "<cmd>BufferClose<CR>";
            options = {
              desc = "Delete buffer";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>bo";
            action = "<cmd>BufferCloseAllButCurrentOrPinned<CR>";
            options = {
              desc = "Delete other buffers";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>bp";
            action = "<cmd>BufferPin<CR>";
            options = {
              desc = "Pin buffer";
              silent = true;
            };
          }

          # Window and Zellij navigation
          {
            mode = "n";
            key = "<C-h>";
            action = "<cmd>ZellijNavigateLeftTab<CR>";
            options = {
              desc = "Focus left";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<C-j>";
            action = "<cmd>ZellijNavigateDown<CR>";
            options = {
              desc = "Focus down";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<C-k>";
            action = "<cmd>ZellijNavigateUp<CR>";
            options = {
              desc = "Focus up";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<C-l>";
            action = "<cmd>ZellijNavigateRightTab<CR>";
            options = {
              desc = "Focus right";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<C-Up>";
            action = "<cmd>resize +2<CR>";
            options = {
              desc = "Increase window height";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<C-Down>";
            action = "<cmd>resize -2<CR>";
            options = {
              desc = "Decrease window height";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<C-Left>";
            action = "<cmd>vertical resize -2<CR>";
            options = {
              desc = "Decrease window width";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<C-Right>";
            action = "<cmd>vertical resize +2<CR>";
            options = {
              desc = "Increase window width";
              silent = true;
            };
          }

          # Editing ergonomics
          {
            mode = "v";
            key = "<";
            action = "<gv";
            options.desc = "Indent left and reselect";
          }

          {
            mode = "v";
            key = ">";
            action = ">gv";
            options.desc = "Indent right and reselect";
          }

          {
            mode = "n";
            key = "<A-j>";
            action = "<cmd>move .+1<CR>==";
            options = {
              desc = "Move line down";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<A-k>";
            action = "<cmd>move .-2<CR>==";
            options = {
              desc = "Move line up";
              silent = true;
            };
          }

          {
            mode = "v";
            key = "<A-j>";
            action = ":move '>+1<CR>gv=gv";
            options = {
              desc = "Move selection down";
              silent = true;
            };
          }

          {
            mode = "v";
            key = "<A-k>";
            action = ":move '<-2<CR>gv=gv";
            options = {
              desc = "Move selection up";
              silent = true;
            };
          }

          {
            mode = "t";
            key = "<Esc><Esc>";
            action = "<C-\\><C-n>";
            options.desc = "Enter normal mode";
          }

          # Diagnostics and lists (Trouble's documented conventions)
          {
            mode = "n";
            key = "<leader>xx";
            action = "<cmd>Trouble diagnostics toggle<CR>";
            options = {
              desc = "Workspace diagnostics";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>xX";
            action = "<cmd>Trouble diagnostics toggle filter.buf=0<CR>";
            options = {
              desc = "Buffer diagnostics";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>xL";
            action = "<cmd>Trouble loclist toggle<CR>";
            options = {
              desc = "Location list";
              silent = true;
            };
          }

          {
            mode = "n";
            key = "<leader>xQ";
            action = "<cmd>Trouble qflist toggle<CR>";
            options = {
              desc = "Quickfix list";
              silent = true;
            };
          }
        ];
      };
    };
}
