{
  nixos.modules.services-ollama =
    { ... }:

    {

      services.ollama = {
        enable = true;
        host = "127.0.0.1";
        port = 11434;
        openFirewall = false;

        # Copy and Paste this per device:
        # services.ollama.package = pkgs.ollama # default (auto)
        # services.ollama.package = pkgs.ollama-cpu;      # force CPU only
        # services.ollama.package = pkgs.ollama-cuda;     # NVIDIA CUDA
        # services.ollama.package = pkgs.ollama-rocm;     # AMD ROCm
        # services.ollama.package = pkgs.ollama-vulkan;   # Vulkan acceleration

        # rocm, cuda, vulkan, or false for cpu
        # DEPRECATED
        # acceleration = "rocm";
        # Optional: preload models, see https://ollama.com/library
        loadModels = [
          "llama3.2:3b"
          "deepseek-r1:1.5b"
        ];

        # The n8n news workflow invokes the models sequentially. Keep only
        # one resident at a time and reject parallel pressure on the desktop
        # GPU from a compromised or accidentally fanned-out workflow.
        environmentVariables = {
          OLLAMA_KEEP_ALIVE = "10m";
          OLLAMA_MAX_LOADED_MODELS = "1";
          OLLAMA_NUM_PARALLEL = "1";
        };
      };

      services.open-webui.enable = true;
      services.open-webui.port = 8081;

      # Ollama's native API has model-management endpoints and no built-in
      # authentication. Keep it on loopback and publish only chat plus a
      # read-only model inventory through a source-restricted nginx gateway.
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        virtualHosts.ollama-loom-gateway = {
          serverName = "nixos.guildedthorn.arpa";
          listen = [
            {
              addr = "0.0.0.0";
              port = 11435;
            }
          ];
          extraConfig = ''
            allow 172.16.25.62;
            deny all;
            client_max_body_size 256k;
          '';
          locations = {
            "= /api/chat" = {
              proxyPass = "http://127.0.0.1:11434/api/chat";
              # Ollama rejects non-loopback Host headers as DNS-rebinding
              # protection. Do not inherit nginx's generic `$host` proxy
              # header for this narrow gateway.
              recommendedProxySettings = false;
              extraConfig = ''
                if ($request_method != POST) {
                  return 405;
                }
                proxy_http_version 1.1;
                proxy_set_header Host 127.0.0.1:11434;
                proxy_set_header Connection "";
                proxy_buffering off;
                proxy_connect_timeout 5s;
                proxy_read_timeout 300s;
                proxy_send_timeout 30s;
              '';
            };
            "= /api/tags" = {
              proxyPass = "http://127.0.0.1:11434/api/tags";
              recommendedProxySettings = false;
              extraConfig = ''
                if ($request_method != GET) {
                  return 405;
                }
                proxy_http_version 1.1;
                proxy_set_header Host 127.0.0.1:11434;
                proxy_set_header Connection "";
              '';
            };
            "/".return = 404;
          };
        };
      };

      systemd.services.nginx = {
        wants = [ "ollama.service" ];
        after = [ "ollama.service" ];
      };

      networking.firewall.extraCommands = ''
        iptables -w -A nixos-fw -p tcp -s 172.16.25.62/32 \
          --dport 11435 -j nixos-fw-accept
      '';

    };
}
