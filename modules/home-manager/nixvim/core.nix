{
  # Base editor: options, UI, treesitter, git, search, and quality-of-life
  # plugins. The concerns that break independently live in sibling files
  # (keymaps.nix, lsp.nix, completion.nix, debug.nix), each behind its own
  # enable flag defaulting on — same pattern as hyprland/.
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
      options.thorn.programs.nixvim.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nixvim editor configuration.";
      };

      config = lib.mkIf cfg.enable {
        programs.nixvim = {
          nixpkgs.config.allowUnfree = true;

          enable = true;
          defaultEditor = true;
          globals.mapleader = " ";

          extraPackages = with pkgs; [
            fzf
            ripgrep
            fd
          ];

          opts = {
            confirm = true;
            cursorline = true;
            foldlevel = 99;
            foldlevelstart = 99;
            ignorecase = true;
            inccommand = "split";
            mouse = "";
            number = true;
            relativenumber = true;
            scrolloff = 6;
            showmode = false;
            sidescrolloff = 8;
            signcolumn = "yes";
            smartcase = true;
            splitbelow = true;
            splitright = true;
            timeoutlen = 300;
            undofile = true;
            updatetime = 250;
            wrap = false;
          };

          plugins = {

            #################################################
            # UI / Core
            #################################################
            alpha = {
              enable = true;
              theme = "dashboard";
            };
            lualine.enable = true;
            web-devicons.enable = true;
            which-key = {
              enable = true;
              settings.spec = [
                {
                  __unkeyed-1 = "<leader>b";
                  group = "Buffers";
                }
                {
                  __unkeyed-1 = "<leader>c";
                  group = "Code";
                }
                {
                  __unkeyed-1 = "<leader>d";
                  group = "Debug";
                }
                {
                  __unkeyed-1 = "<leader>f";
                  group = "Find";
                }
                {
                  __unkeyed-1 = "<leader>g";
                  group = "Git";
                }
                {
                  __unkeyed-1 = "<leader>h";
                  group = "Git hunks";
                }
                {
                  __unkeyed-1 = "<leader>x";
                  group = "Diagnostics";
                }
              ];
            };

            barbar.enable = true;
            yazi.enable = true;

            toggleterm = {
              enable = true;
              settings = {
                direction = "float";
                open_mapping = "[[<c-\\>]]";
              };
            };

            #################################################
            # Search
            #################################################

            telescope = {
              enable = true;
              extensions.fzf-native.enable = true;
            };

            #################################################
            # Git
            #################################################

            gitsigns = {
              enable = true;
              settings.on_attach = ''
                function(bufnr)
                  local gs = package.loaded.gitsigns
                  local function map(mode, lhs, rhs, desc)
                    vim.keymap.set(mode, lhs, rhs, {
                      buffer = bufnr,
                      silent = true,
                      desc = desc,
                    })
                  end

                  map("n", "]h", gs.next_hunk, "Next Git hunk")
                  map("n", "[h", gs.prev_hunk, "Previous Git hunk")
                  map("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
                  map("v", "<leader>hs", ":Gitsigns stage_hunk<CR>", "Stage selected hunk")
                  map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
                  map("v", "<leader>hr", ":Gitsigns reset_hunk<CR>", "Reset selected hunk")
                  map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
                  map("n", "<leader>hb", gs.blame_line, "Blame line")
                end
              '';
            };
            neogit.enable = true;

            #################################################
            # Editing quality-of-life
            #################################################

            todo-comments.enable = true;
            nvim-autopairs.enable = true;
            nvim-surround.enable = true;
            indent-blankline.enable = true;
            sleuth.enable = true;
            lastplace.enable = true;

            #################################################
            # Notifications / UX
            #################################################

            fidget.enable = true;
            tiny-inline-diagnostic.enable = true;
            trouble.enable = true;

            #################################################
            # Treesitter (clean + essential only)
            #################################################

            treesitter = {
              enable = true;
              highlight.enable = true;
              indent.enable = true;
              folding.enable = true;
            };

            treesitter-context = {
              enable = true;
              settings = {
                max_lines = 4;
                min_window_height = 40;
              };
            };

            #################################################
            # Language-specific extras
            #################################################

            dotnet.enable = true;
            nix.enable = true;
            nix-develop.enable = true;
            yuck.enable = true;

            #################################################
            # Terminal / session tooling
            #################################################

            zellij.enable = true;
            zellij-nav.enable = true;

            #################################################
            # Misc (kept but trimmed)
            #################################################

            wakatime.enable = true;
            project-nvim = {
              enable = true;
              enableTelescope = true;
            };
            auto-session.enable = true;

            cloak.enable = true;
            neocord = {
              enable = true;
              # Upstream currently assumes a UI channel exists during setup,
              # which breaks `nvim --headless`. Configure it on UIEnter below.
              callSetup = false;
            };
          };

          extraConfigLua = ''
            vim.api.nvim_create_autocmd("TextYankPost", {
              callback = function()
                vim.highlight.on_yank({ timeout = 150 })
              end,
              desc = "Highlight yanked text",
            })

            vim.api.nvim_create_autocmd("UIEnter", {
              once = true,
              callback = function()
                if #vim.api.nvim_list_uis() > 0 then
                  require("neocord").setup({})
                end
              end,
              desc = "Start Discord Rich Presence for interactive sessions",
            })
          '';
        };

        stylix.targets.nixvim.enable = true;
      };
    };
}
