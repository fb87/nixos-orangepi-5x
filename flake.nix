{
  description = "NixOS Installer AArch64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05-small";
    home-manager = {
      url = https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz;
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

	patches = [ ./patches/u-boot/0001-sdmmc-enable.patch ];

        nativeBuildInputs = with pkgs; [
	  (python3.withPackages(p: with p; [ 
	    setuptools pyelftools
	  ]))

	  swig ncurses gnumake bison flex openssl bc
	] ++ [ rkbin ];

        configurePhase = ''
          make ARCH=arm evb-rk3588_defconfig
        '';

        buildPhase = ''
          patchShebangs tools scripts
	  ROCKCHIP_TPL=${rkbin}/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin BL31=${rkbin}/rk3588_bl31_v1.40.elf make -j8
        '';

        installPhase = ''
	  mkdir $out
          cp u-boot-rockchip.bin $out
        '';
      };

      nixos-orangepi-5x = pkgs.stdenvNoCC.mkDerivation {
        pname = "nixos-orangepi-5x";
        version = "unstable";

        src = ./.;

        installPhase = ''
          mkdir $out
          cp -Rf * $out/
        '';
      };


      buildConfig = { pkgs, lib, ... }: {
        boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.callPackage ./board/kernel {
          src = inputs.linux-rockchip;
        });

        # most of required modules had been builtin
        boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];

        boot.kernelParams = [ "console=ttyS2,1500000" "console=tty1" "loglevel=0" ];
        boot.initrd.includeDefaultModules = false;

        hardware = {
          deviceTree = {
            name = "rockchip/rk3588s-orangepi-5b.dtb";
          };

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
          };

          enableRedistributableFirmware = true;
          firmware = [
            (pkgs.callPackage ./board/firmware { })
          ];
        };

        networking.networkmanager.enable = true;
        networking.wireless.enable = false;

        powerManagement.cpuFreqGovernor = "ondemand";

        nixpkgs.config.allowUnfree = true;

        environment.systemPackages = with pkgs; [
          git htop neovim neofetch

	  # only wayland can utily GPU as of now
          wayland waybar swaylock swayidle foot wdisplays wofi

	  chromium
        ];

        programs.sway = {
          enable = true;
          wrapperFeatures.gtk = true;
        };

        services.openssh.enable = true;
        system.stateVersion = "23.05";
      };
    in
    rec
    {
      # to boot from SDCard
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
          (buildConfig { inherit pkgs; lib = nixpkgs.lib; })
          ({ pkgs, lib, ... }: {
            boot.initrd.availableKernelModules = lib.mkForce [ ];
            networking.hostName = "nixos";

            users.users.nixos = {
              initialPassword = "nixos";
              isNormalUser = true;
              extraGroups = [ "networkmanager" "wheel" ];
              home = "${nixos-orangepi-5x}";

              # embedded the flake into the installer image cuz I don't want to download!
              packages = [
                nixos-orangepi-5x u-boot
              ];
            };

	    # rockchip bootloader needs 16MiB+
            sdImage.firmwarePartitionOffset = 32;
            sdImage.compressImage = true;
            sdImage.postBuildCommands = ''
              dd if=\${u-boot}/u-boot-rockchip.bin of=$img seek=64 conv=notrunc 
            '';
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
                loader = {
                  grub.enable = false;
                  generic-extlinux-compatible.enable = true;
                };

                initrd.luks.devices."Encrypted".device = "/dev/disk/by-partlabel/Encrypted";
                initrd.availableKernelModules = lib.mkForce [ "dm_mod" "dm_crypt" "encrypted_keys" ];
              };

              fileSystems."/" =
                {
                  device = "none";
                  fsType = "tmpfs";
                  options = [ "mode=0755" ];
                };

              fileSystems."/boot" =
                {
                  device = "/dev/disk/by-partlabel/Firmwares";
                  fsType = "vfat";
                };

              fileSystems."/nix" =
                {
                  device = "/dev/mapper/Encrypted";
                  fsType = "btrfs";
                  options = [ "subvol=nix,compress=zstd,noatime" ];
                };

              fileSystems."/home/dao" =
                {
                  device = "/dev/mapper/Encrypted";
                  fsType = "btrfs";
                  options = [ "subvol=usr,compress=zstd,noatime" ];
                };

              networking.hostName = "singoc";
              networking.networkmanager.enable = true;

              time.timeZone = "Asia/Ho_Chi_Minh";
              i18n.defaultLocale = "en_US.UTF-8";

              users.users.dao = {
                isNormalUser = true;
                initialPassword = "dao";
                extraGroups = [ "wheel" "networkmanager" ];
                packages = with pkgs; [
                  glances
                  librewolf
                  neofetch
                  pavucontrol
                  lxappearance
                ];
              };

              programs.sway.enable = true;

              virtualisation.podman.enable = true;

              hardware.pulseaudio.enable = true;

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
                  min-free = ${toString (100 * 1024 * 1024)}
                  max-free = ${toString (1024 * 1024 * 1024)}
                '';
              };
            })
        ];
      };

      homeConfigurations.dao = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ({ pkgs, ... }: {
            home.stateVersion = "23.05";
            home.username = "dao";
            home.homeDirectory = "/home/dao";

            home.packages = with pkgs; [
              file
              qemu
              unzip
              usbutils
              direnv
              neofetch
              chromium
            ];

            home.file = {
              ".local/bin/firefox".source = pkgs.writeScript "firefox" ''
                	         MOZ_ENABLE_WAYLAND=1 librewolf
                	       '';

              ".local/bin/chrome".source = pkgs.writeScript "chrome" ''
                	         ${pkgs.chromium}/bin/chromium-browser --ignore-gpu-blocklist --enable-zero-copy --ozone-platform=wayland
                	       '';

              ".local/share/fonts/operator-mono-nerd".source = pkgs.fetchFromGitHub {
                owner = "TarunDaCoder";
                repo = "OperatorMono_NerdFont";
                rev = "d8e2ac4";
                sha256 = "sha256-jECkRLoBOYe6SUliAY4CeCFt9jT2GjS6bLA7c/N4uaY=";
              };

              ".config/user-dirs.dirs" = {
                text = ''
                  XDG_DESKTOP_DIR="$HOME/pubs"
                  XDG_DOWNLOAD_DIR="$HOME/data"
                  XDG_TEMPLATES_DIR="$HOME/pubs"
                  XDG_PUBLICSHARE_DIR="$HOME/pubs"
                  XDG_VIDEOS_DIR="$HOME/meds"
                  XDG_PICTURES_DIR="$HOME/meds"
                  XDG_MUSIC_DIR="$HOME/meds"
                  XDG_DOCUMENTS_DIR="$HOME/docs"
                '';
              };

              ".config/nvim/init.lua".source = pkgs.fetchurl {
                url = "https://raw.githubusercontent.com/fb87/init.nvim/master/init.lua";
                sha256 = "sha256-ZnxDhufkpnH1y9ZoxgXaMykDGkYjwWHDlRr6hwcxuxQ=";
              };

	      ".local/share/fonts/typewroter".source = pkgs.fetchzip {
	        url = "https://dl.dafont.com/dl/?f=typewriter_condensed";
		name = "typewriter.zip";
		extension = "zip";
		stripRoot = false;
		sha256 = "sha256-O7BeFWvAt5EzAXw9MxigvTKFaba75uNDsEP0Asoq28E=";
	      };
            };

            programs = {
              home-manager.enable = true;

              git = {
                enable = true;
                userName = "Si Dao";
                userEmail = "dao@singoc.com";
                extraConfig = {
                  core = { whitespace = "trailing-space,space-before-tab"; };
                };
              };

              starship = {
                enable = true;
              };

              bash = {
                enable = true;

                shellAliases = {
                  gd = "git dot";

                  ".." = "cd ..";

                  hmw = "home-manager switch -b bak --flake $HOME/.nixos";
                  hme = "$EDITOR $HOME/.nixos/modules/home.nix";
                  nxe = "$EDITOR $HOME/.nixos/flake.nix";
                  nxs = "sudo nixos-rebuild switch --flake $HOME/.nixos";
                  ns = "nix search nixpkgs --no-write-lock-file";
                };

                bashrcExtra = ''
                                     # get rid of nano
                                     export EDITOR=nvim

                                     # wanna use local bin
                                     export PATH=$HOME/.local/bin:$PATH

                                     # use VI mode instead of Emacs
                                     set -o vi

                  		   if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
                                       exec sway
                                     fi

                                     eval "$(direnv hook bash)"
                '';
              };
            };
          })
        ];
      };

      packages.aarch64-linux.default = nixosConfigurations.installer.config.system.build.sdImage;
    };
}
