{
  description = "NixOS Installer AArch64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05-small";

    mesa-panfork = {
      url = "gitlab:panfork/mesa/csf";
      flake = false;
    };

    linux-rockchip = {
      url = "github:Joshua-Riek/linux-rockchip/linux-5.10-gen-rkr4";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, ... }:
  let
  pkgs = import nixpkgs { system = "aarch64-linux"; };
  rk3588s-atf-blob = pkgs.stdenvNoCC.mkDerivation {
    pname = "rk3588s-atf-blob";
    version = "0.0.1";
    
    src = pkgs.fetchFromGitHub {
      owner = "armbian";
      repo = "rkbin";
      rev = "5d409529dbbc12959111787e77c349b3e832bc52";
      sha256 = "sha256-cLBn7hBhVOKWz0bxJwRWyKJ+Au471kzQNoc8d8sVqlM=";
    };
    
    installPhase = ''
      mkdir $out && cp rk35/*.* $out/
    '';
  };

  rk3588s-uboot = pkgs.stdenv.mkDerivation {
    pname = "rk3588s-uboot";
    version = "2017.09-rk3588";

    src = pkgs.fetchFromGitHub {
      owner = "orangepi-xunlong";
      repo = "u-boot-orangepi";
      rev = "v2017.09-rk3588";
      sha256 = "sha256-L4cnmyzjFu4WRE0JTzQh2kNxD5CKxbYj5NgFT2EUynI=";
    };
    patches = [ ./patches/uboot/f1.patch ./patches/uboot/f2.patch ./patches/uboot/f3.patch ];

    buildInputs = [ rk3588s-atf-blob pkgs.bc pkgs.dtc pkgs.python2 ];

    configurePhase = ''
      make ARCH=arm orangepi_5b_defconfig
    '';

    buildPhase = ''
      patchShebangs arch/arm/mach-rockchip

      make ARCH=arm BL31=${rk3588s-atf-blob}/rk3588_bl31_v1.32.elf \
        spl/u-boot-spl.bin u-boot.dtb u-boot.itb
      tools/mkimage -n rk3588 -T rksd -d \
        ${rk3588s-atf-blob}/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.08.bin:spl/u-boot-spl.bin \
        idbloader.img
    '';

    installPhase = ''
      mkdir $out
      cp u-boot.itb idbloader.img $out
    '';
  };
 in rec
 {
    nixosConfigurations.opi5x = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
        ( { pkgs, lib, ...}: {
          boot.kernelPackages = pkgs.linuxPackagesFor (pkgs.callPackage ./board/kernel {
            src = inputs.linux-rockchip;
          });

          boot.kernelParams = [ "console=ttyS2,1500000" "console=tty1" ];
          boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];
          boot.initrd.includeDefaultModules = false;
          boot.initrd.availableKernelModules = lib.mkForce [ ];

          hardware = {
            deviceTree = {
              name = "rockchip/rk3588s-orangepi-5b.dtb";
            };

            opengl = {
              enable = true;
              package =
                lib.mkForce
                  (
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

          networking.hostName = "singoc";
          networking.networkmanager.enable = true;
          networking.wireless.enable = false;
          
          powerManagement.cpuFreqGovernor = "ondemand";

          nixpkgs.config.allowUnfree = true;

          time.timeZone = "Asia/Ho_Chi_Minh";

          i18n.defaultLocale = "en_US.UTF-8";
          users.users.nixos = {
            initialPassword = "nixos";
            isNormalUser = true;
            extraGroups = [ "networkmanager" "wheel" ];
          };

          environment.systemPackages = with pkgs; [
            git htop neovim
          ];

          services.openssh.enable = true;

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
              min-free = ${toString (100 * 1024 * 1024)}
              max-free = ${toString (1024 * 1024 * 1024)}
            '';
          };

          system.stateVersion = "23.05";
          # 32 MiB offset, should be enough for bootloader
          sdImage.firmwarePartitionOffset = 32;
          sdImage.compressImage = true;
          sdImage.postBuildCommands = ''
             dd if=\${rk3588s-uboot}/idbloader.img of=$img seek=64 conv=notrunc 
             dd if=\${rk3588s-uboot}/u-boot.itb of=$img seek=16384 conv=notrunc 
          '';
        })
      ];
    };

    opi5x = nixosConfigurations.opi5x.config.system.build.sdImage;
  };
}
