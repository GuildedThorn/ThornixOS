{
  nixos.modules.services-ollama =
    { ... }:

    {

      services.ollama = {
        enable = true;

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
      };

      services.open-webui.enable = true;
      services.open-webui.port = 8081;

    };
}
