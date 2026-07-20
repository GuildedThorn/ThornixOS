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
            mouse = "";
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
            which-key.enable = true;

            barbar.enable = true;
            yazi.enable = true;

            toggleterm.enable = true;

            #################################################
            # Search
            #################################################

            telescope.enable = true;

            #################################################
            # Git
            #################################################

            gitsigns = {
              enable = true;
              settings.on_attach = ''
                function(bufnr)
                  local gs = package.loaded.gitsigns
                  local opts = { buffer = bufnr, silent = true }

                  vim.keymap.set("n", "]h", gs.next_hunk, opts)
                  vim.keymap.set("n", "[h", gs.prev_hunk, opts)
                  vim.keymap.set("n", "<leader>hs", gs.stage_hunk, opts)
                  vim.keymap.set("n", "<leader>hr", gs.reset_hunk, opts)
                  vim.keymap.set("n", "<leader>hp", gs.preview_hunk, opts)
                  vim.keymap.set("n", "<leader>hb", gs.blame_line, opts)
                end
              '';
            };
            neogit.enable = true;

            #################################################
            # Editing quality-of-life
            #################################################

            comment.enable = true;
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
              settings = {
                highlight = {
                  enable = true;
                };
                indent_enable = true;
                folding = true;
                autoLoad = true;
                incremental_selection.enable = true;
              };
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
            project-nvim.enable = true;
            auto-session.enable = true;

            cloak.enable = true;
            neocord.enable = true;
          };
        };

        stylix.targets.nixvim.enable = true;
      };
    };
}
