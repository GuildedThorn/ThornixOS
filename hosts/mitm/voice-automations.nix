builtins.concatLists [
  (import ./voice-automations/overview.nix)
  (import ./voice-automations/home.nix)
  (import ./voice-automations/operations.nix)
  (import ./voice-automations/media.nix)
  (import ./voice-automations/device.nix)
]
