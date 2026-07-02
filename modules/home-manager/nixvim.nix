{
  homeManager.modules.thorn =
    { pkgs, ... }:
    {
      programs.nixvim = {
        nixpkgs.config.allowUnfree = true;

        enable = true;
        defaultEditor = true;
        globals.mapleader = " ";

        extraPackages = with pkgs; [
          fzf
          ripgrep
          fd

          # formatters / linters
          stylua
          black
          prettier
        ];

        opts = {
          mouse = "";
        };

        keymaps = [

          {
            mode = "n";
            key = "<leader>yy";
            action = "\"+yy";
            options.desc = "Copy current line";
          }

          {
            mode = "n";
            key = "<leader>ya";
            action = "ggVG\"+y";
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
            action.__raw = "function() require('dap').step_over() end";
            options = {
              desc = "Debug: Step Over";
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
            action.__raw = "function() require('dap').step_out() end";
            options = {
              desc = "Debug: Step Out";
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

          -- JavaScript / TypeScript: vscode-js-debug
          dap.adapters["pwa-node"] = {
            type = "server",
            host = "localhost",
            port = "''${port}",
            executable = {
              command = "${pkgs.vscode-js-debug}/bin/js-debug",
              args = { "''${port}" },
            },
          }
          local js_config = {
            {
              type = "pwa-node",
              request = "launch",
              name = "Launch file",
              program = "''${file}",
              cwd = "''${workspaceFolder}",
            },
            {
              type = "pwa-node",
              request = "attach",
              name = "Attach to process",
              processId = require("dap.utils").pick_process,
              cwd = "''${workspaceFolder}",
            },
          }
          dap.configurations.javascript = js_config
          dap.configurations.typescript = js_config
          dap.configurations.typescriptreact = js_config
          dap.configurations.javascriptreact = js_config
        '';

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

          #################################################
          # COMPLETION (CLEAN + CONTROLLED)
          #################################################

          blink-cmp = {
            enable = true;
            setupLspCapabilities = true;

            settings = {
              keymap.preset = "enter";

              appearance = {
                use_nvim_cmp_as_default = true;
                nerd_font_variant = "mono";
              };

              completion.menu = {
                enabled = true;
                auto_show = true;
              };

              signature.enabled = true;

              sources = {
                default = [
                  "lsp"
                  "path"
                  "buffer"
                  "snippets"
                ];
              };
            };
          };

          blink-cmp-git.enable = true;

          blink-emoji.enable = true;
          blink-indent.enable = true;

          #################################################
          # Snippets (low-noise setup)
          #################################################

          luasnip.enable = true;
          friendly-snippets.enable = true;

          #################################################
          # Debugging
          #################################################

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
}
