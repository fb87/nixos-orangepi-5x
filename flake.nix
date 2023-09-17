{
  description = "NixOS on OPI5x";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05-small";

  outputs = { self, nixpkgs }: 
  let
    system = "aarch64-linux";

    pkgs = import nixpkgs { inherit system; };

    rkbin = pkgs.fetchFromGitHub {
      owner = "rockchip-linux";
      repo = "rkbin";
      rev = "b4558da0860ca48bf1a571dd33ccba580b9abe23";
      sha256 = "sha256-KUZQaQ+IZ0OynawlYGW99QGAOmOrGt2CZidI3NTxFw8=";
    };

    uboot = pkgs.stdenv.mkDerivation rec {
      pname = "uboot";
      version = "v2023.07.02";

      src = pkgs.fetchFromGitHub rec {
        owner = "u-boot";
	repo = "${owner}";
	rev = "${version}";
	sha256 = "sha256-HPBjm/rIkfTCyAKCFvCqoK7oNN9e9rV9l32qLmI/qz4=";
      };

      nativeBuildInputs = with pkgs; [
        (python3.withPackages(ps: with ps; [ setuptools pyelftools ]))
	which swig bison flex bc dtc openssl
      ];

      configurePhase = ''
        patchShebangs tools scripts
        make ARCH=arm rock5b-rk3588_defconfig
      '';

      buildPhase = ''
        make ARCH=arm \
	     ROCKCHIP_TPL=${rkbin}/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin \
	     BL31=${rkbin}/bin/rk35/rk3588_bl31_v1.40.elf \
	     -j$(nproc)
      '';

      installPhase = ''
        cp u-boot-rockchip.bin $out
      '';
    };
  in
  rec {
    nixosConfigurations.opi5x = nixpkgs.lib.nixosSystem {
      inherit system;

      modules = [
	({pkgs, lib, ...}: {
          imports = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ];
	  boot.kernelPackages = pkgs.linuxPackages_latest;
	  boot.kernelParams = [ "console=ttyS2,1500000" "console=tty1" "boot.shell_on_fail" ];
          boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];

	  hardware.deviceTree.name = "rockchip/rk3588s-rock-5a.dtb";
	  hardware.deviceTree.overlays = [
            {
              # enable sdcard node
              name = "enable-sdcard";
              dtsText = ''
                /dts-v1/;
                /plugin/;
                / {
		    compatible = "rockchip,rk3588";

		    fragment@0 {
                      target = <&sdmmc>;

                      __overlay__ {
                        status = "okay";
                      };
                    };
		};
              '';
            }
	  ];

          # allow firmwares to be packed
	  nixpkgs.config.allowUnfree = true;
	  hardware.enableAllFirmware = true;

	  users.users.nixos = {
            initialPassword = "nixos";
            isNormalUser = true;
            description = "NixOS User";
            extraGroups = [ "users" "networkmanager" "wheel" ];
          };

	  sdImage.firmwarePartitionOffset = 16; # 16MiB for bootloader
          sdImage.compressImage = false;
          sdImage.postBuildCommands = "dd if=${uboot} of=$img seek=64 conv=notrunc";

          system.stateVersion = "23.05";
	})
      ];
    };

    images.opi5x = nixosConfigurations.opi5x.config.system.build.sdImage;
  };
}
