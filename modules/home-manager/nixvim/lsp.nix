{
  inputs,
  ...
}:
{
  # LSP servers, buffer-local LSP keymaps (via LspAttach autocmd), and
  # formatting (conform + the formatter binaries it shells out to).
  # Kill-switch: thorn.programs.nixvim.lsp.enable = false.
  homeManager.modules.thorn =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.nixvim;
      hostName = osConfig.networking.hostName;
      thornixFlake = toString inputs.self;
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
            isort
            nixfmt
            prettier
            shfmt
          ];

          extraConfigLua = ''
            vim.api.nvim_create_autocmd("LspAttach", {
              callback = function(args)
                local bufnr = args.buf
                local function map(mode, lhs, rhs, desc)
                  vim.keymap.set(mode, lhs, rhs, {
                    buffer = bufnr,
                    silent = true,
                    desc = desc,
                  })
                end

                -- Neovim already provides K, grn, gra, gri, grr, gO, [d, and ]d.
                map("n", "gd", vim.lsp.buf.definition, "Go to definition")
                map("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
                map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code action")
                map("n", "<leader>cr", vim.lsp.buf.rename, "Rename symbol")
                map("n", "<leader>cd", vim.diagnostic.open_float, "Line diagnostics")
                map("n", "<leader>cf", function()
                  require("conform").format({
                    async = true,
                    lsp_format = "fallback",
                  })
                end, "Format buffer")
                map("n", "<leader>cs", "<cmd>Trouble symbols toggle focus=false<CR>", "Document symbols")
                map("n", "<leader>cl", "<cmd>Trouble lsp toggle focus=false win.position=right<CR>", "LSP locations")
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
              bashls.enable = true;
              lua_ls.enable = true;
              pyright.enable = true;
              clangd.enable = true;
              jsonls.enable = true;
              marksman.enable = true;
              ts_ls.enable = true;
              eslint.enable = true;
              intelephense.enable = true;
              yamlls.enable = true;
              rust_analyzer = {
                enable = true;
                installRustc = true;
                installCargo = true;
              };
              nixd = {
                enable = true;
                settings = {
                  nixpkgs = {
                    expr = "import ${inputs.nixpkgs} { }";
                  };
                  formatting = {
                    command = [ "nixfmt" ];
                  };
                  options = {
                    nixos.expr = ''
                      (builtins.getFlake "${thornixFlake}").nixosConfigurations.${hostName}.options
                    '';
                    "home-manager".expr = ''
                      let
                        flake = builtins.getFlake "${thornixFlake}";
                        host = flake.nixosConfigurations.${hostName};
                      in
                      (flake.inputs.home-manager.lib.homeManagerConfiguration {
                        pkgs = host.pkgs;
                        modules = [
                          flake.inputs.stylix.homeModules.stylix
                          flake.homeManagerModules.thorn
                          {
                            home.username = "thorn";
                            home.homeDirectory = "/home/thorn";
                            nix.package = host.config.nix.package;
                          }
                        ];
                        extraSpecialArgs.osConfig = host.config;
                      }).options
                    '';
                  };
                };
              };

              typos_lsp.enable = true;
            };

            #################################################
            # LINTING (COMPLEMENTARY TO LSP DIAGNOSTICS)
            #################################################

            lint = {
              enable = true;
              autoInstall.enable = true;
              autoCmd.event = [
                "BufEnter"
                "BufWritePost"
                "InsertLeave"
              ];
              # nixd already exposes libnixf parser/semantic diagnostics;
              # Statix adds non-overlapping Nix anti-pattern checks.
              lintersByFt.nix = [ "statix" ];
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
                  python = [
                    "isort"
                    "black"
                  ];

                  javascript = [ "prettier" ];
                  javascriptreact = [ "prettier" ];
                  typescript = [ "prettier" ];
                  typescriptreact = [ "prettier" ];
                  json = [ "prettier" ];
                  jsonc = [ "prettier" ];
                  css = [ "prettier" ];
                  scss = [ "prettier" ];
                  html = [ "prettier" ];
                  markdown = [ "prettier" ];
                  yaml = [ "prettier" ];
                  sh = [ "shfmt" ];
                };

                format_on_save = {
                  lsp_format = "fallback";
                  timeout_ms = 1000;
                };
              };
            };
          };
        };
      };
    };
}
