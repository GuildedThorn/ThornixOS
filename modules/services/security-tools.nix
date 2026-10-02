{
  lib,
  pkgs,
  ...
}:
{
  nixos.modules.services-security-tools =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.securityTools;

      # ltrace 0.7.91's dejagnu suite fails on this kernel/userland (15
      # unexpected failures), so the package cannot build with checks on.
      # Disable its test phase rather than dropping the tool.
      ltrace = pkgs.ltrace.overrideAttrs (_: {
        doCheck = false;
      });

      # Every group is off by default: a security workstation should opt in to
      # the tool families it actually exercises rather than inherit the union
      # of everything the fleet has ever needed.
      group =
        description:
        lib.mkOption {
          type = lib.types.bool;
          default = false;
          example = true;
          description = description;
        };

      # Grouped the way Kali groups its menu, which follows the MITRE ATT&CK
      # Enterprise tactics. Tactic groups hold tools whose primary use maps to
      # that phase of an engagement; the trailing non-tactic groups hold
      # cross-cutting tool families that do not belong to a single phase.
      packageGroups = {
        reconnaissance = with pkgs; [
          nmap
          masscan
          rustscan
          naabu
          arp-scan
          netdiscover
          amass
          subfinder
          dnsx
          dnsrecon
          massdns
          puredns
          shuffledns
          httpx
          katana
          ffuf
          feroxbuster
          gobuster
          dirsearch
          zmap
          sslscan
          testssl
          ssldump
          wafw00f
          recon-ng
          theharvester
          snallygaster
          gf
          unfurl
          waybackurls
          qsreplace
          subjack
          dnsutils
        ];

        resourceDevelopment = with pkgs; [
          interactsh
          tlsx
          asnmap
          cdncheck
          altdns
          uncover
          pacu
          prowler
        ];

        initialAccess = with pkgs; [
          exploitdb
          burpsuite
          sqlmap
          nuclei
          wfuzz
          commix
          wpscan
          joomscan
          nikto
          xsstrike
          dalfox
          kerbrute
          powershell
          freerdp
        ];

        execution = with pkgs; [
          metasploit
          powershell
          pwncat
          netexec
          python3Packages.impacket
          socat
          busybox
          chisel
          ligolo-ng
        ];

        # Thin on purpose: persistence on a target is mostly the payload
        # framework's own modules, so this group contributes the remote
        # execution and cloud-IAM tooling those modules drive.
        persistence = with pkgs; [
          netexec
          python3Packages.impacket
          powershell
          pacu
          chisel
        ];

        privilegeEscalation = with pkgs; [
          netexec
          python3Packages.impacket
          powershell
          pwncat
          pwntools
          ropgadget
          python3Packages.ropper
          checksec
          gdb
          strace
          ltrace
          libfaketime
          detect-it-easy
          binutils
          pspy
          python3Packages.capstone
        ];

        defenseEvasion = with pkgs; [
          frida-tools
          upx
          detect-it-easy
          libfaketime
          binutils
          mkcert
          python3Packages.impacket
        ];

        credentialAccess = with pkgs; [
          hashcat
          john
          hash-identifier
          hexedit
          hydra
          ncrack
          medusa
          cewl
          crunch
          responder
          aircrack-ng
          hcxtools
          bettercap
          ettercap
          keepassxc
          certipy
          python3Packages.impacket
        ];

        discovery = with pkgs; [
          netexec
          responder
          python3Packages.impacket
          python3Packages.bloodhound
          ldapdomaindump
          enum4linux
          samba
          openldap
          kerbrute
          certipy
          nmap
          arp-scan
          dnsx
          amass
          dnsrecon
          pacu
          prowler
        ];

        lateralMovement = with pkgs; [
          chisel
          ligolo-ng
          sshuttle
          netexec
          python3Packages.impacket
          samba
          freerdp
          openvpn
          openconnect
          wireguard-tools
          socat
        ];

        collection = with pkgs; [
          sleuthkit
          binwalk
          foremost
          exiftool
          wireshark
          tshark
          tcpdump
          pcapfix
          sngrep
          volatility3
          yara
          hashdeep
          sqlite
          xxd
        ];

        commandAndControl = with pkgs; [
          chisel
          ligolo-ng
          gost
          iodine
          stunnel
          ngrok
          frp
          socat
          proxychains-ng
          tor
          openvpn
        ];

        exfiltration = with pkgs; [
          rclone
          gost
          iodine
          stunnel
          ngrok
          frp
          tor
          openvpn
          socat
        ];

        impact = with pkgs; [
          metasploit
          netexec
          python3Packages.impacket
          bettercap
          ettercap
          mdk4
          masscan
        ];

        exploitation = with pkgs; [
          metasploit
          exploitdb
        ];

        reversing = with pkgs; [
          ghidra
          radare2
          cutter
          rizin
          detect-it-easy
          binutils
        ];

        pwn = with pkgs; [
          gdb
          pwntools
          pwncat
          ropgadget
          python3Packages.ropper
          checksec
          python3Packages.capstone
          python3Packages.z3-solver
          radare2
          cutter
          aflplusplus
          honggfuzz
          gef
          pwninit
        ];

        wireless = with pkgs; [
          aircrack-ng
          bettercap
          kismet
          hcxtools
          mdk4
        ];

        forensics = with pkgs; [
          sleuthkit
          binwalk
          foremost
          exiftool
          wireshark
          tshark
          pcapfix
          sngrep
          volatility3
          yara
          hashdeep
          testdisk
          ddrescue
          autopsy
        ];

        utilities = with pkgs; [
          jq
          yq
          gron
          fzf
          ripgrep
          fd
          bat
          eza
          htop
          btop
          tmux
          neovim
          socat
          wget
          curl
          httpie
          file
          xxd
          hexedit
          sqlite
          p7zip
          unzip
          strace
          ltrace
          openssl
          netcat
        ];
      };

      packageLists = lib.mapAttrsToList (
        name: enabled: if enabled then packageGroups.${name} else [ ]
      ) cfg.groups;

      # Engagement targets are deliberately a data file rather than option
      # values. Labs hand out a fresh address every time a machine is spawned,
      # so these lines churn far faster than a rebuild, and the file stays
      # readable and editable without touching any Nix source.
      targetsPath = "/etc/security-tools/targets";

      targetEntry = "[[:space:]]*([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})[[:space:]]+([^[:space:]]+)[[:space:]]*";

      targetLines =
        if cfg.targets.file == null then
          [ ]
        else
          lib.filter (line: lib.trim line != "" && !(lib.hasPrefix "#" (lib.trim line))) (
            lib.splitString "\n" (builtins.readFile (toString cfg.targets.file))
          );

      # Malformed lines are dropped here so the assertion below reports them
      # instead of the module crashing on a null capture.
      parsedTargets = lib.concatMap (
        line:
        let
          matched = builtins.match targetEntry line;
        in
        if matched == null then
          [ ]
        else
          # builtins.match yields the capture groups only, with no leading
          # element for the whole match, so the address is group 0.
          [
            {
              address = builtins.elemAt matched 0;
              name = builtins.elemAt matched 1;
            }
          ]
      ) targetLines;

      badTargetLines = lib.filter (line: builtins.match targetEntry line == null) targetLines;

      # Merged only on request. /etc/hosts wins over DNS, so a stale line here
      # keeps sending a name to an address the lab has already reclaimed, and
      # nothing short of a rebuild clears it.
      resolvedTargets = lib.listToAttrs (
        map (target: {
          name = target.name;
          value = [ target.address ];
        }) parsedTargets
      );

      targetsQuery = pkgs.writeShellApplication {
        name = cfg.targets.command;
        runtimeInputs = [ pkgs.gawk ];
        text = ''
          targets=${targetsPath}

          usage() {
            cat <<'EOF'
          Usage: ${cfg.targets.command} [options] [name]

            (no arguments)  list every target as "<address> <name>"
            -a, --address   print the address for NAME
            -n, --name      print the name for ADDRESS
          EOF
          }

          if [ ! -r "$targets" ]; then
            echo "${cfg.targets.command}: $targets is missing" >&2
            exit 1
          fi

          # Comments and blank lines are kept in the file for readability, so
          # filter them out of every lookup rather than at write time.
          entries() {
            gawk '!/^[[:space:]]*(#|$)/ { print $1, $2 }' "$targets"
          }

          # A miss has to fail loudly: an empty expansion in
          # $(...) turns into a silently wrong target rather than a broken
          # command, and the engagement only notices much later.
          require_match() {
            local matched
            matched=$(cat)
            if [ -z "$matched" ]; then
              echo "${cfg.targets.command}: no target matches $1 $2" >&2
              exit 1
            fi
            printf '%s\n' "$matched"
          }

          case "''${1-}" in
            -a|--address)
              [ "$#" -eq 2 ] || {
                usage >&2
                exit 2
              }
              entries | gawk -v want="$2" '$2 == want { print $1 }' | require_match name "$2"
              ;;
            -n|--name)
              [ "$#" -eq 2 ] || {
                usage >&2
                exit 2
              }
              entries | gawk -v want="$2" '$1 == want { print $2 }' | require_match address "$2"
              ;;
            -h|--help)
              usage
              ;;
            "")
              entries
              ;;
            *)
              entries | gawk -v want="$1" '$2 == want { print $1 }' | require_match name "$1"
              ;;
          esac
        '';
      };
    in
    {
      options.thorn.securityTools = {
        enable = lib.mkEnableOption "the security tooling suite";

        groups = {
          reconnaissance = group "MITRE ATT&CK Reconnaissance: asset discovery, enumeration and fingerprinting";
          resourceDevelopment = group "MITRE ATT&CK Resource Development: acquiring infrastructure, capabilities and cloud footholds";
          initialAccess = group "MITRE ATT&CK Initial Access: exploit surface, fuzzing, payload delivery and remote client tooling";
          execution = group "MITRE ATT&CK Execution: remote code execution frameworks and listeners";
          persistence = group "MITRE ATT&CK Persistence: remote service creation and cloud IAM persistence";
          privilegeEscalation = group "MITRE ATT&CK Privilege Escalation: local exploitation, ptrace and binary analysis";
          defenseEvasion = group "MITRE ATT&CK Defense Evasion: packing, instrumentation and anti-forensics";
          credentialAccess = group "MITRE ATT&CK Credential Access: offline cracking, online brute force and credential harvesting";
          discovery = group "MITRE ATT&CK Discovery: host, AD and cloud inventory from a foothold";
          lateralMovement = group "MITRE ATT&CK Lateral Movement: pivoting, tunnels and remote management protocols";
          collection = group "MITRE ATT&CK Collection: disk, memory, packet and file collection";
          commandAndControl = group "MITRE ATT&CK Command and Control: tunnels, proxies and covert channels";
          exfiltration = group "MITRE ATT&CK Exfiltration: transfer tooling and anonymising transports";
          impact = group "MITRE ATT&CK Impact: denial of service and destructive capability";

          exploitation = group "Exploitation frameworks and exploit archives, spanning several tactics";
          reversing = group "Static and dynamic reverse engineering toolchains";
          pwn = group "Binary exploitation and fuzzing development toolchains";
          wireless = group "802.11 capture, injection and credential recovery";
          forensics = group "Disk, memory and container image forensics";
          utilities = group "General purpose CLI tooling that security work leans on";
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          example = with pkgs; [ cobalt ];
          description = ''
            Host-specific packages to add alongside the enabled groups. Use this
            for tools that are not packaged in nixpkgs or that this host needs
            regardless of which groups it enables.
          '';
        };

        containers = lib.mkEnableOption "Docker, for tools that are only packaged as container images";

        targets = {
          file = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            example = ./htb-targets;
            description = ''
              Plain-text engagement target list, one "<address> <name>" pair
              per line, with "#" comments. It is installed verbatim as
              ${targetsPath} for the ${cfg.targets.command} command to query.
              Edit it and rebuild — it is data, not code, so this is the only
              thing that has to change when a lab hands out a new address.
            '';
          };

          command = lib.mkOption {
            type = lib.types.str;
            default = "htb-targets";
            example = "htb-targets";
            description = ''
              Name of the generated lookup command. It lists every target, or
              resolves one name to an address (and one address to a name) with
              -a/--address and -n/--name.
            '';
          };

          etcHosts = lib.mkEnableOption ''
            Also merge the target list into networking.hosts, so the names
            resolve for everything that uses the system resolver — browsers,
            curl, ssh, editors — instead of only through the lookup command.

            The cost is staleness: /etc/hosts outranks DNS, so an address the
            lab has already reclaimed keeps being handed out for that name
            until the list is edited and the host is rebuilt.
          '';
        };

        hostTuning = lib.mkEnableOption ''
          Kernel tunables these tools need: unprivileged user namespaces for
          sandboxed and instrumented binaries, and higher inotify limits for
          large concurrent file-watching scans.
        '';
      };

      config = lib.mkIf cfg.enable {
        # kingfisher 1.113.0's install-check expects the version string in
        # `--version`/`--help` output, but the release binary reports a
        # different string, so the check always fails upstream.
        nixpkgs.overlays = [
          (final: prev: {
            kingfisher = prev.kingfisher.overrideAttrs (_: {
              doInstallCheck = false;
            });
          })
        ];

        environment.systemPackages =
          (lib.concatLists packageLists)
          ++ cfg.extraPackages
          ++ lib.optional (cfg.targets.file != null) targetsQuery;

        # A malformed line would otherwise never resolve, and the failure only
        # shows up mid-engagement as a name that mysteriously does not resolve.
        assertions =
          lib.optional (cfg.targets.file != null) {
            assertion = badTargetLines == [ ];
            message = ''
              ${toString cfg.targets.file} has lines that are not "<address> <name>":
              ${lib.concatStringsSep "\n" badTargetLines}
            '';
          }
          ++ lib.optional (cfg.targets.file != null) {
            assertion = builtins.pathExists (toString cfg.targets.file);
            message = "The security tools target list ${toString cfg.targets.file} does not exist";
          };

        environment.etc."security-tools/targets" = lib.mkIf (cfg.targets.file != null) {
          source = cfg.targets.file;
        };

        networking.hosts = lib.mkIf (cfg.targets.etcHosts && cfg.targets.file != null) resolvedTargets;

        virtualisation.docker.enable = lib.mkIf cfg.containers true;

        boot.kernel.sysctl = lib.mkIf cfg.hostTuning {
          "kernel.unprivileged_userns_clone" = 1;
          "fs.inotify.max_user_watches" = 524288;
          "fs.inotify.max_user_instances" = 512;
        };
      };
    };
}
