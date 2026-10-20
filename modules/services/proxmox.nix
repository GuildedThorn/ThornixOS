{ inputs, ... }:
{
  nixos.modules.services-proxmox =
    {
      lib,
      config,
      pkgs,
      ...
    }:

    let
      system = config.nixpkgs.system;

      # proxmox-nixos does not build its packages from the host's own package
      # set: its overlay hard-codes `import nixpkgs-stable { ... }` from the
      # pin it carries.  Two packages from that pin do not build, so construct
      # the same package set from an extended copy of our nixpkgs-stable input
      # and feed that to proxmox-nixos' package definitions instead.
      #
      # python3.12/3.13-sh 2.2.2: two asyncio tests deadlock/fail under the
      # build sandbox; skip them exactly as proxmox-nixos does upstream.
      #
      # perl XML-Twig 3.54: nixpkgs-stable carries a precedence patch that no
      # longer applies to the 3.54 tarball ("1 out of 1 hunk ignored").  Both
      # consumers only use it while rendering pve docs, so drop the patch.
      stablePkgs = inputs.nixpkgs-stable.legacyPackages.${system}.extend (
        _final: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (_pyfinal: pyprev: {
              sh = pyprev.sh.overridePythonAttrs (old: {
                disabledTests = (old.disabledTests or [ ]) ++ [
                  "test_done_callback_no_deadlock"
                  "test_timeout_overstep"
                ];
              });
            })
          ];
          perlPackages = prev.perlPackages // {
            XMLTwig = prev.perlPackages.XMLTwig.overrideAttrs (_: {
              patches = [ ];
            });
          };
          # Stock nixpkgs-stable's libvncserver carries a patch that no longer
          # applies; proxmox-nixos builds vncterm against its own pinned fork.
          libvncserver =
            (import "${inputs.proxmox-nixos.inputs.nixpkgs-libvncserver}" {
              inherit system;
            }).libvncserver;
        }
      );

      pvePackages = import "${inputs.proxmox-nixos}/pkgs" { pkgs = stablePkgs; };
    in
    {

      # The `qm` binary can resolve to the pve-ha-manager wrapper, which does
      # not include cdrkit in PATH when generating cloud-init images.
      environment.systemPackages = [ pkgs.cdrkit ];

      # pve-manager ships notification templates below /usr/share, but the
      # NixOS profile does not link that subtree by default.  Without these
      # templates Proxmox's notification test fails before SMTP is attempted.
      environment.pathsToLink = [ "/usr/share/pve-manager" ];

      services.openssh.settings.AcceptEnv = lib.mkForce [
        "LANG"
        "LC_*"
      ];

      services.proxmox-ve = {
        enable = true;
        openFirewall = false;
      };

      # pvedaemon and friends run against the glibc of proxmox-nixos's pinned
      # nixpkgs-stable.  PAM modules built from a newer root nixpkgs reference
      # symbol versions that glibc does not provide, so pam_unix.so fails to
      # dlopen and every login 401s.  Serve all PAM stacks from the same pin
      # the proxmox packages use; older-module-into-newer-glibc is safe.
      security.pam.package = stablePkgs.linux-pam;

      nixpkgs.overlays = [
        (_final: _prev: pvePackages)
      ];
    };
}
