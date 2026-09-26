{ ... }:
{
  # Drift detection for the hand-built detonation lab VMs.
  #
  # These VMs are created, patched and snapshotted outside this repo, so
  # `nixos-rebuild` cannot see them and nothing in Git records what they are
  # supposed to look like. That gap already bit once: the guest-agent flag that
  # every piece of detonation automation depends on was unset, and the only
  # symptom was a control channel that reported the VM as unreachable. Declaring
  # the inventory here and checking it on a timer turns that class of silent
  # break into a logged one, and gives whoever patches a VM a place to record
  # what they changed.
  #
  # This is deliberately a check and not a provisioner. The existing
  # services-proxmox-provisioner path builds fresh NixOS guests with
  # nixos-anywhere and waits on systemd units over SSH, none of which applies to
  # a Windows image with a six-deep snapshot chain and no credentials this repo
  # holds.
  nixos.modules.services-flare-lab =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.nixos.modules.services-flare-lab;

      check = pkgs.writeShellApplication {
        name = "flare-lab-check";
        runtimeInputs = [
          # tr, sort, printf
          pkgs.coreutils
          # field parsing of the Proxmox config format
          pkgs.gawk
          pkgs.jq
        ];
        text = builtins.readFile ./flare-lab-check.sh;
      };

      inventoryFile = pkgs.writeText "flare-lab-inventory.json" (builtins.toJSON cfg.inventory);
    in
    {
      options.nixos.modules.services-flare-lab = {
        enable = lib.mkEnableOption "the FLARE detonation lab configuration drift check";

        inventory = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule (
              { name, ... }: {
                options = {
                  description = lib.mkOption {
                    type = lib.types.str;
                    description = "What this VM is for, shown in the report.";
                  };
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "The Proxmox VM name, matched against the config file.";
                  };
                  bridge = lib.mkOption {
                    type = lib.types.str;
                    default = "vmbr1";
                    description = ''
                      Host bridge the VM must be attached to. The lab segment is
                      isolated, so a VM silently landing on vmbr0 would put it on the
                      trusted LAN with its detonation traffic.
                    '';
                  };
                  macAddress = lib.mkOption {
                    type = lib.types.str;
                    description = ''
                      MAC address. Checked because the lab DHCP-free addressing
                      and the INetSim sinkhole depend on stable guest identity, and
                      a re-created VM gets a new one.
                    '';
                  };
                  memoryMiB = lib.mkOption {
                    type = lib.types.int;
                    description = ''
                      RAM. The detonation budget is derived from this: a RAM disk
                      large enough to be useful has to fit in what is left over
                      after Windows.
                    '';
                  };
                  cores = lib.mkOption {
                    type = lib.types.int;
                    description = "vCPU count.";
                  };
                  guestAgent = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = ''
                      Whether the QEMU guest agent must be enabled. This is the
                      flag whose absence silently breaks all remote control.
                    '';
                  };
                  onboot = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = ''
                      Whether the VM should start when the node boots. Declared
                      rather than assumed so that leaving the lab VMs off at boot is
                      a recorded decision.
                    '';
                  };
                };
              }
            )
          );
          default = { };
          description = ''
            Lab VMs to check, keyed by vmid. Each entry is compared against
            /etc/pve/qemu-server/<vmid>.conf on this node.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Runs at every boot, and the oneshot failing does not hold up the
        # boot: a drifted lab VM is a reporting problem, not a reason to leave
        # an operator staring at a degraded console.
        systemd.services.flare-lab-inventory = {
          description = "Check the FLARE lab VMs against their declared configuration";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe check + " --inventory ${inventoryFile}";
          };
        };

        # The lab VMs outlive many reboots of the hypervisor, so a boot-time
        # check alone would not notice a change made weeks later from the web
        # UI or a manual qm set.
        systemd.timers.flare-lab-inventory = {
          description = "Periodic FLARE lab VM configuration drift check";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 06:17:00";
            RandomizedDelaySec = "3h";
            Persistent = true;
            Unit = "flare-lab-inventory.service";
          };
        };

        # Exposed so CI can at least build the checker with the host closure.
        system.build.flareLabCheck = check;
      };
    };
}
