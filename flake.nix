{
  description = "NixOS Installer AArch64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05-small";

    mesa-panfork = {
      url = "gitlab:panfork/mesa/csf";
      flake = false;
    };

    linux-rockchip = {
      url = "github:armbian/linux-rockchip/rk-5.10-rkr5.1";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, ... }:
    let
      user = "dao";

      pkgs = import nixpkgs { system = "aarch64-linux"; };
      rkbin = pkgs.stdenvNoCC.mkDerivation {
        pname = "rkbin";
        version = "unstable-b4558da";

        src = pkgs.fetchFromGitHub {
          owner = "rockchip-linux";
          repo = "rkbin";
          rev = "b4558da0860ca48bf1a571dd33ccba580b9abe23";
          sha256 = "sha256-KUZQaQ+IZ0OynawlYGW99QGAOmOrGt2CZidI3NTxFw8=";
        };

        # we just need TPL and BL31 but it doesn't hurt,
        # follow single point of change to make life easier
        installPhase = ''
          mkdir $out && cp bin/rk35/rk3588* $out/
        '';
      };

      u-boot = pkgs.stdenv.mkDerivation rec {
        pname = "u-boot";
        version = "v2023.07.02";

        src = pkgs.fetchFromGitHub {
          owner = "u-boot";
          repo = "u-boot";
          rev = "${version}";
          sha256 = "sha256-HPBjm/rIkfTCyAKCFvCqoK7oNN9e9rV9l32qLmI/qz4=";
        };

        # u-boot for evb is not enable the sdmmc node, which cause issue as
        # b-boot cannot detect sdcard to boot from
        # the order of boot also need to swap, the eMMC mapped to mm0 (not same as Linux kernel)
        # will then tell u-boot to load images from eMMC first instead of sdcard
        # FIXME: this is strage cuz the order seem correct in Linux kernel
        patches = [ ./patches/u-boot/0001-sdmmc-enable.patch ];

        nativeBuildInputs = with pkgs; [
          (python3.withPackages (p: with p; [
            setuptools
            pyelftools
          ]))

          swig
          ncurses
          gnumake
          bison
          flex
          openssl
          bc
        ] ++ [ rkbin ];

        configurePhase = ''
          make ARCH=arm evb-rk3588_defconfig
        '';

        buildPhase = ''
          patchShebangs tools scripts
          make -j$(nproc) \
            ROCKCHIP_TPL=${rkbin}/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin \
            BL31=${rkbin}/rk3588_bl31_v1.40.elf
        '';

        installPhase = ''
          mkdir $out
          cp u-boot-rockchip.bin $out
        '';
      };

      rk-valhal = pkgs.stdenv.mkDerivation rec {
	pname = "valhall";
	version = "1.9.0";

	phases = "installPhase fixupPhase";

        buildInputs = with pkgs; [ wayland stdenv.cc.cc.lib libdrm xorg.libxcb xorg.libX11 ];
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];

	src = pkgs.fetchurl {
	  url = "https://github.com/JeffyCN/mirrors/raw/libmali/lib/aarch64-linux-gnu/libmali-valhall-g610-g13p0-x11-wayland-gbm.so";
	  sha256 = "1ksk42qv8byddq2nk3iz0kzgkbxpl5r5pfkfsarldxzb8jsn6478";
	};

	installPhase = ''
          mkdir $out/lib -p
          install -m551 $src $out/lib/libmali.so.1

          ln -s libmali.so.1 $out/lib/libmali-valhall-g610-g13p0-x11-wayland-gbm.so
          for l in libEGL.so libEGL.so.1 libgbm.so.1 libGLESv2.so libGLESv2.so.2 libOpenCL.so.1; do ln -s libmali.so.1 $out/lib/$l; done
        '';
      };

      nixos-orangepi-5x = pkgs.stdenvNoCC.mkDerivation {
        pname = "nixos-orangepi-5x";
        version = "unstable";

        src = ./.;

        installPhase = ''
          tar czf $out *
        '';
      };


      buildConfig = { pkgs, lib, ... }: {
        boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.callPackage ./board/kernel {
          src = inputs.linux-rockchip;
        });

        # most of required modules had been builtin
        boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];

        boot.kernelParams = [
          "console=ttyS2,1500000" # serial port for debugging
          "console=tty1" # should be HDMI
          "loglevel=4" # more verbose might help
        ];
        boot.initrd.includeDefaultModules = false; # no thanks, builtin modules should be enough

        hardware = {
          deviceTree = { name = "rockchip/rk3588s-orangepi-5b.dtb"; };

          opengl = {
            enable = true;
            package = lib.mkForce (
              (pkgs.mesa.override {
                galliumDrivers = [ "panfrost" "swrast" ];
                vulkanDrivers = [ "swrast" ];
              }).overrideAttrs (_: {
                pname = "mesa-panfork";
                version = "23.0.0-panfork";
                src = inputs.mesa-panfork;
              })
            ).drivers;
	    extraPackages = [ rk-valhal ];
          };

          firmware = [ (pkgs.callPackage ./board/firmware { }) ];

          pulseaudio.enable = true;
        };

        networking = {
          networkmanager.enable = true;
          wireless.enable = false;
        };

        environment.systemPackages = with pkgs; [
          git
          htop
          neofetch

          # only wayland can utily GPU as of now
          wayland
          waybar
          swaylock
          swayidle
          foot
          wdisplays
          wofi
	  gnome.adwaita-icon-theme
        ];

        environment.loginShellInit = ''
          # https://wiki.archlinux.org/title/Sway
	  export GDK_BACKEND=wayland
          export MOZ_ENABLE_WAYLAND=1
	  export QT_QPA_PLATFORM=wayland
	  export XDG_SESSION_TYPE=wayland

          if [ -z "$WAYLAND_DISPLAY" ] && [ "_$XDG_VTNR" == "_1" ] && [ "_$(tty)" == "_/dev/tty1" ]; then
	    dunst&
            exec ${pkgs.sway}/bin/sway
          fi

	  alias e=nvim
	  alias rebuild='sudo nixos-rebuild switch --flake .'
        '';

        programs = {
	  sway.enable = true;

	  starship.enable = true;
	  neovim.enable = true;
	  neovim.defaultEditor = true;
	};

        system.stateVersion = "23.05";
      };
    in
    rec
    {
      # to boot from SDCard
      nixosConfigurations.live = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
          (buildConfig { inherit pkgs; lib = nixpkgs.lib; })
          ({ pkgs, lib, ... }: {
            # all modules we need are builtin already, the nixos default profile might add
            # some which is not available, force to not use any other.
            boot.initrd.availableKernelModules = lib.mkForce [ ];

            users.users.nixos = {
              initialPassword = "nixos";
              isNormalUser = true;
              extraGroups = [ "networkmanager" "wheel" ];

              packages = [
                # all scripts bellow run as batch, no failure check

                (pkgs.writeScriptBin "opi5b-update-firmware-2-emmc" ''
                  set -x

                  [ -f /boot/firmware/u-boot-rockchip.bin ] && \
                    sudo dd if=/boot/firmware/u-boot-rockchip.bin of=/dev/mmcblk0 seek=64
                '')

                (pkgs.writeScriptBin "opi5b-unmount-emmc" ''
                  set -x

                  # unmount everything those leftover
                  mount | awk '/mmcblk0|dev\/mapper|Firmwares|Encrypted|mnt/{print $1}' | xargs umount > /dev/null 2>&1
                '')

                (pkgs.writeScriptBin "opi5b-format-emmc" ''
                  set -x

                  # unmount everything those leftover
                  opi5-unmount-emmc
                  ${pkgs.cryptsetup}/bin/cryptsetup luksClose /dev/disk/by-partlabel/Encrypted > /dev/null 2>&1

                  # create partition table
                  ${pkgs.parted}/bin/parted -s /dev/mmcblk0 -- mktable gpt
                  ${pkgs.parted}/bin/parted -s /dev/mmcblk0 -- mkpart Firmwares fat32 16MiB 512MiB
                  ${pkgs.parted}/bin/parted -s /dev/mmcblk0 -- mkpart Encrypted btrfs 512MiB 100%
                  ${pkgs.parted}/bin/parted -s /dev/mmcblk0 -- set 1 boot on
                  ${pkgs.parted}/bin/parted -s /dev/mmcblk0 -- print

                  # format the boot partition in advanced
                  mkfs.vfat -F32 /dev/mmcblk0p1

                  # expect crypt device not yet openned or mounted
                  ${pkgs.cryptsetup}/bin/cryptsetup luksFormat /dev/disk/by-partlabel/Encrypted
                  ${pkgs.cryptsetup}/bin/cryptsetup luksOpen /dev/disk/by-partlabel/Encrypted Encrypted

                  # format partition and create subvolumes
                  mkfs.btrfs /dev/mapper/Encrypted
                  mkdir -p /mnt && mount /dev/mapper/Encrypted /mnt
                  btrfs subvolume create /mnt/nix
                  btrfs subvolume create /mnt/usr
                  umount /mnt
                '')

                (pkgs.writeScriptBin "opi5b-mount-root" ''
                  set -x

                  # nerds might repeatly run over and over
                  opi5-unmount-emmc

                  # where is the root?
                  mkdir -p /mnt
                  mount -t tmpfs -o size=8G,mode=755 none /mnt

                  # create the archors
                  mkdir -p /mnt/{boot,nix}
                  mount -t btrfs -o subvol=nix,compress=zstd,noatime /mnt/nix
                  mount /dev/disk/by-partlabel/Firmwares /mnt/boot

                  # final check before hangout
                  mount
                '')

                (pkgs.writeScriptBin "opi5b-install-2-emmc" ''
                  set -x

                  tmp=$(mktemp -d)

                  # we are trying to customize the flake, let not try copy
                  [ -f $PWD/flake.nix ] && tmp=$PWD
                  [ -f $tmp/flake.nix ] || tar xf firmware/nixos-orangepi-5x.tar.gz -C $tmp

                  [ -f $tmp/flake.nix ] && nix build $tmp/flake.nix#singoc
                '')
              ];
            };

            # rockchip bootloader needs 16MiB+
            sdImage = {
              # 16MiB should be enough (u-boot-rockchip.bin ~ 10MiB)
              firmwarePartitionOffset = 16;
              firmwarePartitionName = "Firmwares";

              compressImage = true;
              expandOnBoot = true;

              # u-boot-rockchip.bin is all-in-one bootloader blob, flashing to the image should be enough
              populateFirmwareCommands = "dd if=${u-boot}/u-boot-rockchip.bin of=$img seek=64 conv=notrunc";

              # make sure u-boot available on the firmware partition, cuz we do need this
              # to write to eMMC
              postBuildCommands = ''
                cp ${u-boot}/u-boot-rockchip.bin firmware/
                cp ${nixos-orangepi-5x} firmware/nixos-orangepi-5x.tar.gz
              '';
            };
          })
        ];
      };

      # to install NixOS on eMMC
      nixosConfigurations.singoc = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          (buildConfig { inherit pkgs; lib = nixpkgs.lib; })
          ({ pkgs, lib, ... }:
            {
              boot = {
                loader = { grub.enable = false; generic-extlinux-compatible.enable = true; };
                initrd.luks.devices."Encrypted".device = "/dev/disk/by-partlabel/Encrypted";
                initrd.availableKernelModules = lib.mkForce [ "dm_mod" "dm_crypt" "encrypted_keys" ];
              };

              fileSystems."/" = 	{ device = "none"; fsType = "tmpfs"; options = [ "mode=0755,size=8G" ]; };
              fileSystems."/boot" = 	{ device = "/dev/disk/by-partlabel/Firmwares"; fsType = "vfat"; };
              fileSystems."/nix" = 	{ device = "/dev/mapper/Encrypted"; fsType = "btrfs"; options = [ "subvol=nix,compress=zstd,noatime" ]; };
              fileSystems."/home/${user}" = { device = "/dev/mapper/Encrypted"; fsType = "btrfs"; options = [ "subvol=usr,compress=zstd,noatime" ]; };

              # why not, we have 16GiB RAM
              fileSystems."/tmp" = { device = "none"; fsType = "tmpfs"; options = [ "mode=0755,size=12G" ]; };

              networking = {
                hostName = "singoc";
                networkmanager.enable = true;
              };

              time.timeZone = "Asia/Ho_Chi_Minh";
              i18n.defaultLocale = "en_US.UTF-8";

              users.users.${user} = {
                isNormalUser = true;
                initialPassword = "${user}";
                extraGroups = [ "wheel" "networkmanager" "tty" "video" ];
                packages = with pkgs; [
                  neofetch
                  pavucontrol
		  direnv
		  dunst
		  librewolf
		  nerdfonts
		  wf-recorder
                ];
              };

	      services.getty.autologinUser = "${user}";

	      virtualisation.podman.enable = true;

              nix = {
                settings = {
                  auto-optimise-store = true;
                  experimental-features = [ "nix-command" "flakes" ];
                };

                gc = {
                  automatic = true;
                  dates = "weekly";
                  options = "--delete-older-than 30d";
                };

                # Free up to 1GiB whenever there is less than 100MiB left.
                extraOptions = ''
                  min-free = ${toString ( 100 * 1024 * 1024)}
                  max-free = ${toString (1024 * 1024 * 1024)}
                '';
              };
            })
        ];
      };

      formatter.aarch64-linux = pkgs.nixpkgs-fmt;

      packages.aarch64-linux.default = nixosConfigurations.live.config.system.build.sdImage;
      packages.aarch64-linux.sdwriter = pkgs.writeScript "flash" ''
        echo "= flash to sdcard (/dev/mmcblk1) if presented, requires sudo as well."
        [ -e /dev/mmcblk1 ] && zstdcat result/sd-image/*.zst | \
              sudo dd of=/dev/mmcblk1 bs=8M status=progress
	[ -e /dev/mmcblk1 ] || echo "=  no sdcard found"
      '';
      apps.aarch64-linux.default = { type = "app"; program = "${packages.aarch64-linux.sdwriter}"; };
    };
}
