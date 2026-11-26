{
  # The upstream sc0710 flake installs the built .ko by hand. Nixpkgs' kmod
  # aggregator now expects every out-of-tree module to carry the kernel's
  # per-module signature certificate; use kbuild's modules_install target so
  # the module is signed and sc0710.ko.cer is installed alongside it.
  nixos.modules.hardware-sc0710-signed =
    {
      config,
      lib,
      pkgs,
      sc0710Src,
      ...
    }:
    let
      kernelPackages = config.boot.kernelPackages;
      kernel = config.hardware.sc0710.kernel;
      modDirVersion = kernel.modDirVersion;
      version = lib.fileContents "${sc0710Src}/version";

      signedDriver = pkgs.stdenv.mkDerivation {
        pname = "sc0710";
        inherit version;

        src = sc0710Src.outPath;

        nativeBuildInputs = kernel.moduleBuildDependencies;

        makeFlags = kernelPackages.kernelModuleMakeFlags ++ [
          "KBUILD_DIR=${kernel.dev}/lib/modules/${modDirVersion}/build"
        ];

        buildPhase = ''
          runHook preBuild
          make $makeFlags
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          make $makeFlags -C "${kernel.dev}/lib/modules/${modDirVersion}/build" \
            M="$PWD/build" \
            INSTALL_MOD_PATH="$out" \
            DEPMOD=true \
            modules_install
          runHook postInstall
        '';
      };
    in
    {
      config = lib.mkIf (config.hardware.sc0710.enable or false) {
        # Replace the unsigned module from the sc0710 flake. Keep the other
        # hosts' extra module sets intact.
        boot.extraModulePackages = lib.mkForce [
          config.boot.kernelPackages.nvidia_x11
          signedDriver
        ];
      };
    };
}
