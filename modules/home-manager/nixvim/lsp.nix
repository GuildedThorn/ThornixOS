{
  # LSP servers, buffer-local LSP keymaps (via LspAttach autocmd), and
  # formatting (conform + the formatter binaries it shells out to).
  # Kill-switch: thorn.programs.nixvim.lsp.enable = false.
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
      options.thorn.programs.nixvim.lsp.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nixvim LSP servers and formatting.";
      };

      config = lib.mkIf (cfg.enable && cfg.lsp.enable) {
        programs.nixvim = {
          extraPackages = with pkgs; [
            # formatters / linters
            stylua
            black
            prettier
          ];

          extraConfigLua = ''
            vim.api.nvim_create_autocmd("LspAttach", {
              callback = function(args)
                local bufnr = args.buf
                local opts = { buffer = bufnr, silent = true }

                vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
                vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
                vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
                vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
                vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
                vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
                vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
                vim.keymap.set("n", "[d", function()
                  vim.diagnostic.jump({ count = -1, float = true })
                end, opts)
                vim.keymap.set("n", "]d", function()
                  vim.diagnostic.jump({ count = 1, float = true })
                end, opts)
              end,
            })
          '';

          plugins = {

            #################################################
            # LSP CORE
            #################################################

            lsp = {
              enable = true;
              autoLoad = true;
              inlayHints = true;
            };

            lsp.servers = {
              lua_ls.enable = true;
              pyright.enable = true;
              clangd.enable = true;
              ts_ls.enable = true;
              eslint.enable = true;
              intelephense.enable = true;
              rust_analyzer = {
                enable = true;
                installRustc = true;
                installCargo = true;
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

              typos_lsp.enable = true;
            };

            #################################################
            # FORMATTING (SINGLE SOURCE OF TRUTH)
            #################################################

            conform-nvim = {
              enable = true;

              settings = {
                formatters_by_ft = {
                  nix = [ "nixfmt" ];
                  lua = [ "stylua" ];
                  python = [ "black" ];

                  typescript = [ "prettier" ];
                  typescriptreact = [ "prettier" ];
                };

                format_on_save = {
                  lsp_fallback = true;
                  timeout_ms = 1000;
                };
              };
            };
          };
        };
      };
    };
}
