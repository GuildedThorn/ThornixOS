{
  # Completion (blink-cmp and friends) and snippets.
  # Kill-switch: thorn.programs.nixvim.completion.enable = false.
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
      options.thorn.programs.nixvim.completion.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nixvim completion and snippets.";
      };

      config = lib.mkIf (cfg.enable && cfg.completion.enable) {
        programs.nixvim.plugins = {

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
        };
      };
    };
}
