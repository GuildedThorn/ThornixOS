{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/deck/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.deck = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core
      inputs.jovian-nixos.nixosModules.jovian

      config.nixos.modules.desktop-kde-wle
      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-ssh

      "${inputs.self}/hosts/deck/disko.nix"
      "${inputs.self}/hosts/deck/networking.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/deck/home.nix"; }

      (
        {
          lib,
          pkgs,
          ...
        }:
        let
          linuxVoiceAssistant = pkgs.callPackage ../../packages/linux-voice-assistant.nix { };
          kokoroSource = pkgs.writeText "wyoming-kokoro.py" (
            builtins.readFile ../../packages/wyoming-kokoro.py
          );
          kokoroPython = pkgs.python3.withPackages (
            pythonPackages: with pythonPackages; [
              kokoro
              numpy
              sentence-stream
              spacy-models.en_core_web_sm
              wyoming
            ]
          );
          kokoroConfig = pkgs.fetchurl {
            url = "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/config.json";
            hash = "sha256-WrsB4kA7ByvwPQT94WBEPiCdeg2tSaQjvhUZa5tDwX8=";
          };
          kokoroModel = pkgs.fetchurl {
            url = "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth";
            hash = "sha256-SW26EY0aWPXz2y78iNvcIW4Eg/yJ/m5H7h8sU/GK0eQ=";
          };
          kokoroVoice = pkgs.fetchurl {
            url = "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/voices/af_heart.pt";
            hash = "sha256-CrVwm4/6sZv9hJzRHZj3W2CvdzMlOtDWexI4KhAstP8=";
          };
          modelBenchmarkSource = pkgs.writeText "casita-model-benchmark.py" (
            builtins.readFile ../../packages/casita-model-benchmark.py
          );
          modelBenchmark = pkgs.writeShellApplication {
            name = "casita-model-benchmark";
            text = ''
              exec ${pkgs.python3}/bin/python3 ${modelBenchmarkSource} "$@"
            '';
          };
          voiceRecover = pkgs.writeShellApplication {
            name = "deck-voice-recover";
            runtimeInputs = [ pkgs.systemd ];
            text = ''
              systemctl reset-failed linux-voice-assistant.service
              exec systemctl restart linux-voice-assistant.service
            '';
          };
          voiceHealth = pkgs.writeShellApplication {
            name = "deck-voice-health";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.gnugrep
              pkgs.iproute2
              pkgs.jq
              pkgs.systemd
              pkgs.util-linux
              pkgs.wireplumber
            ];
            text = ''
              set -o nounset -o pipefail

              failure_file=/run/deck-voice-health/failures
              failures=0
              if [[ -r "$failure_file" ]]; then
                read -r failures < "$failure_file" || failures=0
              fi

              reason=
              if ! systemctl is-active --quiet linux-voice-assistant.service; then
                reason="voice assistant service is not active"
              elif ! ss -H -ltn | grep --quiet ':6053'; then
                reason="ESPHome voice endpoint is not listening"
              elif ! env PIPEWIRE_RUNTIME_DIR=/run/pipewire wpctl status >/dev/null 2>&1; then
                reason="PipeWire is not responding"
              else
                health=$(curl --fail --silent --show-error --max-time 4 \
                  http://127.0.0.1:10701/api/health 2>/dev/null) || health=
                if [[ -z "$health" ]]; then
                  thorn_uid=$(id -u thorn)
                  runuser -u thorn -- env XDG_RUNTIME_DIR="/run/user/$thorn_uid" \
                    systemctl --user restart deck-voice-visual.service
                  echo "Deck Voice visual state server was unavailable; restarted it"
                  exit 0
                fi
                if ! jq --exit-status \
                  '.connected == true and .streaming == true and .audio.pipewire == true and .audio.capture == true' \
                  <<< "$health" >/dev/null; then
                  reason="voice connection or microphone capture is stalled"
                fi
              fi

              if [[ -z "$reason" ]]; then
                printf '0\n' > "$failure_file"
                exit 0
              fi

              failures=$((failures + 1))
              printf '%s\n' "$failures" > "$failure_file"
              if ((failures < 2)); then
                echo "Deck Voice health check failed once: $reason"
                exit 0
              fi

              echo "Recovering Deck Voice after $failures checks: $reason"
              printf '0\n' > "$failure_file"
              if [[ "$reason" == "PipeWire is not responding" ]]; then
                systemctl restart pipewire.service
                systemctl restart wireplumber.service
              fi
              systemctl reset-failed linux-voice-assistant.service
              systemctl restart linux-voice-assistant.service
            '';
          };
          voiceE2ESource = pkgs.writeText "deck_voice_e2e.py" (
            builtins.readFile ../../packages/deck_voice_e2e.py
          );
          voiceE2EPython = pkgs.python3.withPackages (
            pythonPackages: with pythonPackages; [
              websocket-client
              wyoming
            ]
          );
          voiceE2E = pkgs.writeShellApplication {
            name = "deck-voice-e2e";
            runtimeInputs = [
              pkgs.alsa-utils
              pkgs.pipewire
              pkgs.systemd
            ];
            text = ''
              exec ${voiceE2EPython}/bin/python3 ${voiceE2ESource} \
                --status-file /var/lib/deck-voice-e2e/status.json \
                --metrics-file /var/lib/node-exporter-textfiles/deck-voice-e2e.prom \
                "$@"
            '';
          };
          voiceE2ETests = pkgs.runCommand "deck-voice-e2e-tests" { } ''
            export PYTHONPATH=${../../packages}
            ${voiceE2EPython}/bin/python3 ${../../packages/deck_voice_e2e_test.py}
            touch "$out"
          '';
        in
        {
          nixpkgs.overlays = [
            inputs.jovian-nixos.overlays.jovian
            (_final: prev: {
              # Current nixpkgs already carries Jovian's MangoHud backports.
              mangohud = prev.mangohud.overrideAttrs (old: {
                patches = lib.unique (old.patches or [ ]);
              });
            })
          ];

          jovian = {
            devices.steamdeck.enable = true;
            steam = {
              enable = true;
              autoStart = true;
              user = "thorn";
              desktopSession = "plasma";
            };
          };

          boot = {
            kernelPackages = lib.mkForce pkgs.linuxPackages_jovian;
            loader = {
              systemd-boot.enable = true;
              efi.canTouchEfiVariables = true;
            };
            initrd.systemd.enable = true;
          };

          services = {
            fwupd.enable = true;
            upower.enable = true;

            ollama = {
              enable = true;
              package = pkgs.ollama-vulkan;
              host = "0.0.0.0";
              port = 11434;
              openFirewall = false;
              loadModels = [
                "granite4.1:3b"
              ];
              environmentVariables = {
                OLLAMA_CONTEXT_LENGTH = "4096";
                OLLAMA_IGPU_ENABLE = "1";
                OLLAMA_KEEP_ALIVE = "60m";
                OLLAMA_MAX_LOADED_MODELS = "1";
                OLLAMA_NUM_PARALLEL = "1";
                OLLAMA_VULKAN = "1";
              };
            };

            pipewire.systemWide = true;

            openssh.settings = {
              KbdInteractiveAuthentication = false;
              PasswordAuthentication = false;
              PermitRootLogin = "prohibit-password";
            };

            # The archived Wyoming satellite has been replaced by the ESPHome
            # Linux Voice Assistant service below.
            wyoming.satellite.enable = false;
          };

          users = {
            groups.voice = { };
            users = {
              root = {
                initialHashedPassword = "!";
                openssh.authorizedKeys.keys = adminSshKeys;
              };
              thorn = {
                openssh.authorizedKeys.keys = adminSshKeys;
                extraGroups = [
                  "audio"
                  "pipewire"
                  "render"
                  "video"
                ];
              };
              voice = {
                isSystemUser = true;
                group = "voice";
                extraGroups = [
                  "audio"
                  "pipewire"
                ];
              };
            };
          };

          environment = {
            # The Deck uses system-wide PipeWire so the voice assistant can
            # share its microphone and speakers with the desktop session.
            sessionVariables = {
              PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
              PULSE_SERVER = "unix:/run/pulse/native";
            };

            systemPackages =
              with pkgs;
              [
                alsa-utils
                mangohud
              ]
              ++ [
                modelBenchmark
                linuxVoiceAssistant
                voiceHealth
                voiceRecover
                voiceE2E
              ];
          };

          system.checks = [ voiceE2ETests ];

          security.sudo.extraRules = [
            {
              users = [ "thorn" ];
              commands = [
                {
                  command = "/run/current-system/sw/bin/deck-voice-recover";
                  options = [ "NOPASSWD" ];
                }
              ];
            }
          ];

          systemd = {
            oomd.enable = true;
            sockets.pipewire = {
              after = [ "pipewire-sysconf.service" ];
              requires = [ "pipewire-sysconf.service" ];
            };
            services.pipewire = {
              after = [ "pipewire-sysconf.service" ];
              requires = [ "pipewire-sysconf.service" ];
            };
            services.pipewire-sysconf.unitConfig.Requisite = "";

            # Keep local inference responsive without allowing it to starve
            # the voice capture path or the Plasma session.
            services.ollama = {
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              serviceConfig = {
                CPUQuota = "600%";
                IOSchedulingClass = "idle";
                MemoryHigh = "6G";
                MemoryMax = "7G";
                Nice = 10;
                OOMScoreAdjust = 500;
                Restart = "on-failure";
                RestartSec = "2s";
              };
            };

            services.linux-voice-assistant = {
              description = "Deck Voice ESPHome satellite";
              wantedBy = [ "multi-user.target" ];
              after = [
                "network-online.target"
                "pipewire.service"
                "wireplumber.service"
              ];
              wants = [
                "network-online.target"
                "pipewire.service"
                "wireplumber.service"
              ];
              conflicts = [ "wyoming-satellite.service" ];
              environment = {
                HOME = "/var/lib/linux-voice-assistant";
                PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
                PULSE_SERVER = "unix:/run/pulse/native";
                PYTHONUNBUFFERED = "1";
                REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
                SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
              };
              serviceConfig = {
                Type = "exec";
                ExecStart = lib.escapeShellArgs [
                  "${linuxVoiceAssistant}/bin/linux-voice-assistant"
                  "--name"
                  "Deck Voice"
                  "--host"
                  "0.0.0.0"
                  "--network-interface"
                  # Keep the Ethernet device identity while binding the API to
                  # every interface; Home Assistant reaches it over OPT1.
                  "enp4s0f3u1u1"
                  "--port"
                  "6053"
                  "--peripheral-host"
                  "127.0.0.1"
                  "--peripheral-port"
                  "6055"
                  "--peripheral-startup-wait"
                  "2"
                  "--preferences-file"
                  "/var/lib/linux-voice-assistant/preferences.json"
                  "--download-dir"
                  "/var/lib/linux-voice-assistant/wakewords"
                  "--audio-input-device"
                  "Audio Coprocessor Internal Microphone"
                  "--audio-input-channels"
                  "1"
                  "--audio-output-device"
                  "pulse/alsa_output.pci-0000_04_00.1.hdmi-stereo-extra2"
                  "--music-output-device"
                  "pulse/alsa_output.pci-0000_04_00.1.hdmi-stereo-extra2"
                  "--mic-volume"
                  "100"
                  "--mic-auto-gain"
                  "20"
                  "--mic-noise-suppression"
                  "3"
                  "--wake-model"
                  "okay_nabu"
                  "--stop-model"
                  "stop"
                  "--continue-conversation-delay"
                  "0.5"
                  "--timer-max-ring-seconds"
                  "300"
                  "--listen-during-wake-sound"
                ];
                User = "voice";
                Group = "voice";
                SupplementaryGroups = [
                  "audio"
                  "pipewire"
                ];
                StateDirectory = "linux-voice-assistant";
                StateDirectoryMode = "0750";
                WorkingDirectory = "/var/lib/linux-voice-assistant";
                Restart = "always";
                RestartSec = "2s";
                TimeoutStopSec = "15s";
                UMask = "0077";
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectHome = true;
                ProtectSystem = "strict";
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_NETLINK"
                  "AF_UNIX"
                ];
              };
            };
            services.casita-kokoro = {
              description = "Casita natural Kokoro Wyoming voice";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              environment = {
                HF_HUB_OFFLINE = "1";
                HOME = "/var/lib/casita-kokoro";
                OMP_NUM_THREADS = "4";
                PYTHONUNBUFFERED = "1";
                TORCH_HOME = "/var/lib/casita-kokoro/torch";
                XDG_CACHE_HOME = "/var/lib/casita-kokoro/cache";
              };
              serviceConfig = {
                Type = "exec";
                ExecStart = lib.escapeShellArgs [
                  "${kokoroPython}/bin/python3"
                  "${kokoroSource}"
                  "--uri"
                  "tcp://0.0.0.0:10201"
                  "--health-host"
                  "0.0.0.0"
                  "--health-port"
                  "10202"
                  "--config"
                  "${kokoroConfig}"
                  "--model"
                  "${kokoroModel}"
                  "--voice"
                  "${kokoroVoice}"
                  "--voice-name"
                  "af_heart"
                  "--speed"
                  "1.04"
                  "--threads"
                  "4"
                  "--piper-host"
                  "172.16.25.2"
                  "--piper-port"
                  "10200"
                ];
                DynamicUser = true;
                StateDirectory = "casita-kokoro";
                WorkingDirectory = "/var/lib/casita-kokoro";
                CPUQuota = "400%";
                MemoryHigh = "2G";
                MemoryMax = "3G";
                Nice = 5;
                Restart = "always";
                RestartSec = "3s";
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectHome = true;
                ProtectSystem = "strict";
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                ];
              };
            };
            services.deck-voice-health = {
              description = "Recover a stalled Deck Voice audio pipeline";
              after = [
                "pipewire.service"
                "wireplumber.service"
                "linux-voice-assistant.service"
              ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${voiceHealth}/bin/deck-voice-health";
                RuntimeDirectory = "deck-voice-health";
                RuntimeDirectoryMode = "0750";
                RuntimeDirectoryPreserve = "yes";
              };
            };
            services.deck-voice-e2e = {
              description = "Prove the Deck Voice acoustic pipeline through HDMI";
              after = [
                "casita-kokoro.service"
                "linux-voice-assistant.service"
                "network-online.target"
                "pipewire.service"
                "wireplumber.service"
              ];
              requires = [
                "casita-kokoro.service"
                "linux-voice-assistant.service"
                "pipewire.service"
                "wireplumber.service"
              ];
              wants = [ "network-online.target" ];
              unitConfig.ConditionACPower = true;
              environment = {
                PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
                PULSE_SERVER = "unix:/run/pulse/native";
              };
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${voiceE2E}/bin/deck-voice-e2e";
                StateDirectory = "deck-voice-e2e";
                StateDirectoryMode = "0755";
                SupplementaryGroups = [
                  "audio"
                  "pipewire"
                ];
                TimeoutStartSec = "2min";
                Nice = 10;
                IOSchedulingClass = "idle";
                UMask = "0022";

                CapabilityBoundingSet = "";
                LockPersonality = true;
                NoNewPrivileges = true;
                PrivateDevices = false;
                PrivateTmp = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectSystem = "strict";
                ReadWritePaths = [ "/var/lib/node-exporter-textfiles" ];
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                ];
                RestrictNamespaces = true;
                RestrictRealtime = true;
                SystemCallArchitectures = "native";
              };
            };
            timers.deck-voice-health = {
              description = "Frequent Deck Voice pipeline health check";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "90s";
                OnUnitInactiveSec = "45s";
                AccuracySec = "5s";
                Unit = "deck-voice-health.service";
              };
            };
            timers.deck-voice-e2e = {
              description = "Run the daily Deck Voice acoustic transaction";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "*-*-* 11:00:00";
                RandomizedDelaySec = "10m";
                AccuracySec = "1m";
                Unit = "deck-voice-e2e.service";
              };
            };
          };

          zramSwap.enable = true;
          system.stateVersion = "25.05";
        }
      )
    ];
  };
}
