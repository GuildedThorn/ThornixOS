{ inputs, ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { pkgs, system, ... }:
    let
      openwrtRelease = "24.10.4";
      kernelVersion = "6.6.110";
      kernelDataSize = 2028386;
      kernelImageSize = kernelDataSize + 64;
      uncompressedKernelSize = 6712000;
      originalDtbSize = 9882;

      bundleKernelAreaSize = 4 * 1024 * 1024;
      initrdPhysicalAddress = 20971520;

      rootKernelModules = [
        "ehci-platform"
        "ohci-platform"
        "usb-storage"
        "sd_mod"
        "ext4"
      ];

      target = "ramips/mt76x8";
      imageName = "openwrt-${openwrtRelease}-ramips-mt76x8-cudy_tr1200-v1";
      downloadBase = "https://downloads.openwrt.org/releases/${openwrtRelease}/targets/${target}";
      kmodBase = "${downloadBase}/kmods/6.6.110-1-7b067dbe1210780507b9fd888c130426";

      sysupgrade = pkgs.fetchurl {
        url = "${downloadBase}/${imageName}-squashfs-sysupgrade.bin";
        hash = "sha256-fgaQ+I4T03CYVo4nw9U0b7UVcVWuVo4bM+jxtYZEqAU=";
      };

      rootKmodFiles = [
        {
          file = "kmod-nls-base_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-WL3G//CxGMTC9pXkXSplfUR/xp6k1/66GaA/Lv2Dmmc=";
        }
        {
          file = "kmod-usb-core_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-eMjVXP0Zu93EXnyOnwFjfb2GrQLOjYsDNryDfB+qTaA=";
        }
        {
          file = "kmod-usb-ehci_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-yw4ntTAUaGXvLzaDZyxM3EiSlyIPjbnt72sB9yQBORY=";
        }
        {
          file = "kmod-usb2_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-5BnbRvUEgEE8PPRrlqswZvxPbQCUNRAQMcW7vRZQvsc=";
        }
        {
          file = "kmod-usb-ohci_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-+qC7BA4auxyXXTVJeOA2XmViOOjRUMmqjDbzhXP2lCw=";
        }
        {
          file = "kmod-scsi-core_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-hNi1aadhfjlnSBYQVo17QYTXE95+yhaJREBgB1DQ+ms=";
        }
        {
          file = "kmod-usb-storage_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-E2CkF1HJ+Vd2vqNEurMNl16U8tF53nSlet159QvVBXI=";
        }
        {
          file = "kmod-lib-crc16_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-f089tfTmVX3j607xpUt6oVfWYO1RMRMXkkQiz9xGwtM=";
        }
        {
          file = "kmod-crypto-hash_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-pBTfAp/QIFgtradaWCYkccbhRxcTEjNT0SPsmJoKqa0=";
        }
        {
          file = "kmod-crypto-crc32c_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-lnaScHl6wz6db5D/Xgf3XFwD/W9ZYDOQoHZxoWC+7DE=";
        }
        {
          file = "kmod-fs-ext4_6.6.110-r1_mipsel_24kc.ipk";
          hash = "sha256-tlosU26SIZfyQDiwWn4W/d7/Ix3c7R8ASU4ILMCaVKw=";
        }
      ];

      rootKmodIpks = map (
        package:
        pkgs.fetchurl {
          url = "${kmodBase}/${package.file}";
          inherit (package) hash;
        }
      ) rootKmodFiles;

      crossSystem = {
        config = "mipsel-unknown-linux-musl";
        gcc = {
          arch = "mips32r2";
          abi = "32";
          float = "soft";
        };
      };

      pkgsCross = import inputs.nixpkgs {
        localSystem = system;
        inherit crossSystem;
        overlays = [
          (final: prev: {
            # Upstream calls both endian variants "mips"; Meson otherwise
            # derives the nonexistent directory name "mipsel".
            libucontext = prev.libucontext.overrideAttrs (old: {
              mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dcpu=mips" ];
            });

            libcap = prev.libcap.override {
              usePam = false;
              withGo = false;
            };

            finit = prev.finit.override {
              libcap = final.libcap;
              shadow = prev.busybox;
              sysctl = prev.busybox;
            };

            util-linux = prev.util-linux.override {
              fetchurl = prev.stdenv.fetchurlBoot;
              cryptsetupSupport = false;
              nlsSupport = false;
              ncursesSupport = false;
              pamSupport = false;
              shadowSupport = false;
              systemdSupport = false;
              translateManpages = false;
              withLastlog = false;
            };
          })
        ];
      };

      openwrtModules =
        pkgsCross.runCommand "openwrt-tr1200-modules-${kernelVersion}"
          {
            srcs = rootKmodIpks;
            nativeBuildInputs = with pkgs; [
              coreutils
              gnutar
              gzip
              kmod
            ];
          }
          ''
            mkdir -p "$out"

            for ipk in $srcs; do
              tar -xOzf "$ipk" ./data.tar.gz | tar -xzf - -C "$out"
            done

            rm -rf "$out/etc"
            moduleDir="$out/lib/modules/${kernelVersion}"
            touch \
              "$moduleDir/modules.builtin" \
              "$moduleDir/modules.builtin.modinfo" \
              "$moduleDir/modules.order"
            depmod -b "$out" ${kernelVersion}
          '';

      vendorKernel = pkgsCross.callPackage (
        {
          stdenvNoCC,
          buildPackages,
          features ? { },
          ...
        }:
        stdenvNoCC.mkDerivation {
          pname = "linux-openwrt-tr1200";
          version = kernelVersion;
          dontUnpack = true;
          nativeBuildInputs = [ buildPackages.coreutils ];
          installPhase = ''
            mkdir -p "$out"
            dd if=${sysupgrade} of="$out/uImage" bs=1 count=${toString kernelImageSize} status=none
            test "$(stat -c%s "$out/uImage")" -eq ${toString kernelImageSize}
          '';
          passthru = {
            inherit features;
            modDirVersion = kernelVersion;
            modules = openwrtModules;
            target = "uImage";
          };
        }
      ) { };

      finixModules = import "${inputs.finix-src}/modules";
      finixSystem = pkgsCross.lib.evalModules {
        class = "nixos";
        specialArgs.modules = finixModules;
        modules = [
          finixModules.default
          { nixpkgs.pkgs = pkgsCross; }
          (
            {
              config,
              lib,
              pkgs,
              ...
            }:
            {
              networking.hostName = "finix-tr1200";

              boot.kernelPackages = pkgs.linuxPackagesFor vendorKernel;
              boot.kernelParams = [
                "console=ttyS0,115200"
                "init=/init"
              ];
              boot.kernelModules = lib.mkForce [ ];
              boot.initrd = {
                compressor = "gzip";
                compressorArgs = [ "-9" ];
                emergencyAccess = true;
                availableKernelModules = lib.mkForce rootKernelModules;
                kernelModules = lib.mkForce rootKernelModules;

                # OpenWrt's stock kernel has no devtmpfs, so load host and
                # storage drivers before coldplug creates the USB block device.
                finit.run.load-root-modules = {
                  priority = 200;
                  conditions = "service/mdevd/ready";
                  script = ''
                    ${pkgs.kmod}/bin/modprobe -a ${lib.escapeShellArgs rootKernelModules}
                  '';
                };

                # Mounting root does not need fsck tools in stage 1. Keeping
                # e2fsprogs out saves RAM when the initramfs is unpacked.
                supportedFilesystems.ext4.packages = lib.mkForce [ ];
              };

              boot.supportedFilesystems.fuse.enable = false;

              fileSystems = lib.mkForce {
                "/" = {
                  device = "/dev/disk/by-label/FINIXROOT";
                  fsType = "ext4";
                  options = [
                    "defaults"
                    "rw"
                  ];
                };
              };

              hardware.console.enable = false;
              services.mdevd.enable = true;

              programs = {
                coreutils.package = pkgs.busybox;
                modprobe.enable = false;
                shadow.enable = false;
              };

              security = {
                pam = {
                  enable = false;
                  services = lib.mkForce { };
                };
                pki.installCACerts = false;
                wrappers = lib.mkForce { };
              };

              environment = {
                binsh = "${pkgs.busybox}/bin/sh";
                pathsToLink = lib.mkForce [
                  "/bin"
                  "/sbin"
                  "/lib"
                ];
                systemPackages = lib.mkForce [
                  pkgs.busybox
                  pkgs.bashInteractive
                  pkgs.kmod
                  pkgs.util-linux
                  config.finit.package
                ];
                etc = {
                  passwd.text = ''
                    root:x:0:0:root:/root:/bin/sh
                  '';
                  group.text = ''
                    root:x:0:
                  '';
                  shadow.text = ''
                    root::1:0:99999:7:::
                  '';
                };
              };

              finit = {
                path = lib.mkForce [
                  pkgs.busybox
                  config.finit.package
                  pkgs.util-linux.mount
                ];
                tasks = {
                  remount-nix-store.enable = false;
                  suid-sgid-wrappers.enable = false;
                  sysctl.command = lib.mkForce (
                    "${pkgs.busybox}/bin/sysctl -p " + config.environment.etc."sysctl.d/60-finix.conf".source
                  );
                };
                ttys.console = {
                  device = "@console";
                  baud = "115200";
                  nowait = true;
                  nologin = true;
                };
              };

              system = {
                activation = {
                  path = lib.mkForce [
                    pkgs.busybox
                    pkgs.util-linux
                  ];
                  scripts.users = lib.mkForce ''
                    mkdir -p /etc /root
                    chmod 0700 /root
                  '';
                };
                build.checkSwitchInhibitors = lib.mkForce (
                  pkgs.writeShellScript "check-switch-inhibitors" "exit 0"
                );
              };

            }
          )
        ];
      };

      systemTopLevel = finixSystem.config.system.topLevel;
      closureInfo = pkgs.closureInfo { rootPaths = [ systemTopLevel ]; };

      rootfs =
        pkgs.runCommand "finix-tr1200-rootfs"
          {
            nativeBuildInputs = with pkgs; [
              coreutils
              e2fsprogs
              fakeroot
              findutils
              gawk
              libfaketime
            ];
          }
          ''
            root="$TMPDIR/root"
            mkdir -p "$out" "$root/nix/store"

            while read -r storePath; do
              cp -a --reflink=auto "$storePath" "$root/nix/store/"
            done < ${closureInfo}/store-paths

            cp ${closureInfo}/registration "$root/nix-path-registration"
            mkdir -p "$root"/{boot,dev,etc,proc,root,run,sys,tmp,var}
            mkdir -p "$root/var"/{cache,db,empty,lib,log,spool}
            ln -sfn /run "$root/var/run"
            cat > "$root/init" <<'EOF'
            #!${pkgsCross.busybox}/bin/sh
            set -eu

            ${systemTopLevel}/activate
            exec ${systemTopLevel}/init
            EOF
            chmod 0755 "$root/init"

            inodeCount=$(find "$root" -print | wc -l)
            dataBlocks=$(du -s -B 4096 --apparent-size "$root" | awk '{ print $1 }')
            blockCount=$((dataBlocks + dataBlocks / 5 + 2 * inodeCount + 16384))
            truncate -s $((blockCount * 4096)) rootfs.img

            faketime -f "1970-01-01 00:00:01" fakeroot sh -euc '
              chown -R 0:0 "$1"
              chown 0:30000 "$1/nix/store"
              chmod 1775 "$1/nix/store"
              chmod 1777 "$1/tmp"
                  mkfs.ext4 \
                    -F \
                    -L FINIXROOT \
                    -U 9a349a01-1200-4f1e-8000-000000000001 \
                    -E hash_seed=9a349a01-1200-4f1e-8000-000000000001,lazy_itable_init=0,lazy_journal_init=0 \
                    -d "$1" \
                    "$2"
            ' -- "$root" rootfs.img

            fsck.ext4 -fn rootfs.img
            mv rootfs.img "$out/finix-rootfs.img"
          '';

      recovery =
        pkgs.runCommand "finix-tr1200-recovery"
          {
            nativeBuildInputs = with pkgs; [
              coreutils
              dtc
              gzip
              ubootTools
              xz
            ];
          }
          ''
            mkdir -p "$out"
            compressedInitrd=${finixSystem.config.boot.initrd.package}/initrd
            initrd=initrd.cpio
            gzip --decompress --stdout "$compressedInitrd" > "$initrd"
            test "$(dd if="$initrd" bs=1 count=6 status=none)" = 070701

            initrdSize=$(stat -c%s "$initrd")
            initrdEnd=$(( ${toString initrdPhysicalAddress} + initrdSize ))

            if (( initrdEnd >= 0x08000000 )); then
              echo "initrd exceeds TR1200 RAM: end=$initrdEnd" >&2
              exit 1
            fi

            dumpimage -T kernel -p 0 -o kernel.lzma ${sysupgrade}
            test "$(stat -c%s kernel.lzma)" -eq ${toString kernelDataSize}
            xz --format=lzma --decompress --stdout kernel.lzma > kernel-with-dtb.bin
            test "$(stat -c%s kernel-with-dtb.bin)" -eq $(( ${toString uncompressedKernelSize} + ${toString originalDtbSize} ))

            dd if=kernel-with-dtb.bin of=kernel.bin bs=1 count=${toString uncompressedKernelSize} status=none
            dd if=kernel-with-dtb.bin of=tr1200.dtb bs=1 skip=${toString uncompressedKernelSize} status=none
            test "$(stat -c%s tr1200.dtb)" -eq ${toString originalDtbSize}
            test "$(fdtget -t i tr1200.dtb / '#address-cells')" -eq 1

            cp tr1200.dtb patched.dtb
            fdtput -t s patched.dtb /chosen bootargs-override "console=ttyS0,115200 init=/init"
            fdtput -t x patched.dtb /chosen linux,initrd-start $(printf '0x%x' ${toString initrdPhysicalAddress})
            fdtput -t x patched.dtb /chosen linux,initrd-end $(printf '0x%x' "$initrdEnd")
            test "$(fdtget -t s patched.dtb /chosen bootargs-override)" = "console=ttyS0,115200 init=/init"
            test "$(fdtget -t x patched.dtb /chosen linux,initrd-start)" = "$(printf '%x' ${toString initrdPhysicalAddress})"
            test "$(fdtget -t x patched.dtb /chosen linux,initrd-end)" = "$(printf '%x' "$initrdEnd")"

            cat kernel.bin patched.dtb > kernel-patched.bin
            uncompressedSize=$(stat -c%s kernel-patched.bin)
            xz \
              --format=lzma \
              --stdout \
              --lzma1=lc=1,lp=2,pb=2,dict=8MiB,nice=273,mf=bt4,mode=normal \
              kernel-patched.bin > kernel-patched.lzma

            i=0
            while [ "$i" -lt 8 ]; do
              byte=$((uncompressedSize >> (8 * i) & 255))
              printf "\\$(printf '%03o' "$byte")"
              i=$((i + 1))
            done | dd of=kernel-patched.lzma bs=1 seek=5 conv=notrunc status=none
            xz --format=lzma --decompress --stdout kernel-patched.lzma > kernel-check.bin
            cmp kernel-patched.bin kernel-check.bin

            export SOURCE_DATE_EPOCH=1760891865
            mkimage \
              -A mips \
              -O linux \
              -T kernel \
              -C lzma \
              -a 0x80000000 \
              -e 0x80000000 \
              -n "MIPS OpenWrt Linux-${kernelVersion}" \
              -d kernel-patched.lzma \
              "$out/kernel.uImage"

            kernelSize=$(stat -c%s "$out/kernel.uImage")
            if (( kernelSize > ${toString bundleKernelAreaSize} )); then
              echo "kernel uImage exceeds 4 MiB bundle area: $kernelSize" >&2
              exit 1
            fi

            cp "$out/kernel.uImage" "$out/recovery.bin"
            truncate -s ${toString bundleKernelAreaSize} "$out/recovery.bin"
            cat "$initrd" >> "$out/recovery.bin"
            test "$(stat -c%s "$out/recovery.bin")" -eq $(( ${toString bundleKernelAreaSize} + initrdSize ))

            dumpimage -T kernel -p 0 -o kernel-check.lzma "$out/recovery.bin"
            cmp kernel-patched.lzma kernel-check.lzma

            cp "$initrd" "$out/initrd.cpio"
            cp patched.dtb "$out/tr1200-finix.dtb"
            ln -s ${rootfs}/finix-rootfs.img "$out/finix-rootfs.img"

            dumpimage -l "$out/recovery.bin" > "$out/uimage.txt"
            cat > "$out/boot.txt" <<'EOF'
            setenv autostart no
            setenv ipaddr 192.168.1.1
            setenv serverip 192.168.1.88
            tftpboot 81000000 recovery.bin
            bootm 81000000
            EOF

            cat > "$out/layout.txt" <<EOF
            bundle-load-address=0x81000000
            kernel-area-size=${toString bundleKernelAreaSize}
            initrd-virtual-start=0x81400000
            initrd-physical-start=$(printf '0x%08x' ${toString initrdPhysicalAddress})
            initrd-physical-end=$(printf '0x%08x' "$initrdEnd")
            initrd-size=$initrdSize
            initrd-format=newc
            EOF

            cd "$out"
            sha256sum \
              kernel.uImage \
              initrd.cpio \
              recovery.bin \
              tr1200-finix.dtb \
              finix-rootfs.img \
              > SHA256SUMS
          '';
    in
    {
      packages = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
        TR1200-finix = recovery;
        TR1200-finix-initrd = finixSystem.config.boot.initrd.package;
        TR1200-finix-rootfs = rootfs;
        TR1200-finix-system = systemTopLevel;
      };
    };
}
