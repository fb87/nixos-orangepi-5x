{
  description = "NixOS Installer AArch64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05-small";
  };

  outputs = { self, nixpkgs }:
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
      sha256 = "sha256-J05zNWwZ26JhYWnUvj/VDYUKaXKEc4Im8KB9NwfBdVU=";
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
    nixosConfigurations.rk3588s = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ( { pkgs, lib, ...}: {
          boot.kernelPackages = pkgs.linuxPackages_6_3;
          boot.kernelParams = [ "console=ttyS2,1500000" "console=tty1" ];
          boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];

          hardware = {
            deviceTree = {
              name = "rockchip/rk3588s-rock-5a.dtb";
            };
          };
          
          users.users.nixos = {
            initialPassword = "nixos";
            isNormalUser = true;
            description = "NixOS User";
            extraGroups = [ "users" "networkmanager" "wheel" ];
          };

          # 32 MiB offset, should be enough for bootloader
          sdImage.firmwarePartitionOffset = 32;
          sdImage.compressImage = false;
          sdImage.postBuildCommands = ''
             dd if=\${rk3588s-uboot}/idbloader.img of=$img seek=64 conv=notrunc 
             dd if=\${rk3588s-uboot}/u-boot.itb of=$img seek=16384 conv=notrunc 
          '';
        })
      ];
    };

    images.rk3588s = nixosConfigurations.rk3588s.config.system.build.sdImage;
  };
}
