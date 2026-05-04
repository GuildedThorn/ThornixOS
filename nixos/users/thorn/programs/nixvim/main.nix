{ pkgs, ... }:
{
  enable = true;

  extraPackages = with pkgs; [
    nixd
    fzf
    ripgrep
    fd
    alejandra
    stylua
    black
    intelephense
  ];

  plugins = {
    #auto-save.enable = true;
    #auto-session.enable = true;
    barbar.enable = true;
    lualine.enable = true;
    neo-tree.enable = true;

    # Notification Daemon
    fidget.enable = true;

    # DiscordRPC
    neocord.enable = true;

    # Git Wrappers
    fugitive.enable = true;
    neogit.enable = true;

    # Language Support
    dotnet.enable = true;
    nix.enable = true;
    nix-develop.enable = true;

    # Language Error Handler
    trouble.enable = true;
    tiny-inline-diagnostic.enable = true;

    comment.enable = true;
    cloak.enable = true;
    web-devicons.enable = true;
    which-key.enable = true;

    treesitter = {
      enable = true;
      settings = {
        highlight = {
          enable = true;
        };
        grammarPackages = pkgs.vimPlugins.nvim-treesitter.allGrammars;
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

    project-nvim.enable = true;

    lsp = {
      enable = true;
      autoLoad = true;
      inlayHints = true;
    };

    lsp.servers = {
      "*" = {
        config = {
          capabilities = {
            textDocument = {
              semanticTokens = {
                multilineTokenSupport = true;
              };
            };
          };
          root_markers = [
            ".git"
          ];
        };
      };
      pyright.enable = true;
      clangd.enable = true;
      lua_ls.enable = true;
      nil_ls.enable = true;
      intelephense = {
        enable = true;
        package = null; # npm install -g intelephense

        # TODO: Hookup to sops-nix
        #init_options = {
        #licenceKey = "";
        #};
      };
      nixd = {
        enable = true;
        settings.nixd = {
          nixpkgs = {
            expr = "import <nixpkgs> {}";
          };
          formatting = {
            command = [ "nixpkgs-fmt" ];
          };
        };
      };
      ts_ls.enable = true;
      rust_analyzer = {
        enable = true;
        installRustc = true;
        installCargo = true;
      };
      typos_lsp = {
        enable = true;
      };
    };

    conform-nvim = {
      enable = true;
      autoLoad = true;

      settings = {
        formatters_by_ft = {
          nix = [ "nixfmt" ];
          lua = [ "stylua" ];
          python = [ "black" ];
        };
        format_on_save = {
          lsp_fallback = true;
          timeout_ms = 500;
        };
      };
    };

    blink-cmp = {
      enable = true;
      setupLspCapabilities = true;

      settings = {
        keymap.preset = "enter";
        appearance = {
          use_nvim_cmp_as_default = true;
          nerd_font_variant = "mono";
        };
        completion = {
          menu = {
            enabled = true;
            auto_show = true;
          };
        };
        signature = {
          enabled = true;
        };
        sources = {
          default = [
            "lsp"
            "path"
            "buffer"
            "snippets"
            "cmdline"
          ];
        };
      };
    };
    blink-cmp-git.enable = true;

    blink-emoji.enable = true;
    blink-indent.enable = true;
    blink-compat.enable = false;

    luasnip.enable = true;
    lspkind.enable = true;

    sleuth.enable = true;

    # Opens the file at your last edit place
    lastplace.enable = true;

    fzf-lua.enable = true;
  };
}
