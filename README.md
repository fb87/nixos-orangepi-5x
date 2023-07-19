# NixOS build for Orangepi 5B

## Overview

Build the installer image which is ready to flash to SDCard to boot.
The final image contains also the `u-boot.itb` and `idbloader.img` flashed.

To build the image, try `./script/build.sh`

## Spec

* Kernel 5.10.160 from [Jushua Riek](https://github.com/Joshua-Riek/linux-rockchip)
* Panfork (for mesa 3D) + mali firmware
* All required firmwares (hopefully) - collected from some prebuilt distro (Armbian, Ubuntu Rockchip)

Check `flake.nix` for more detail.

## Flash the image

```bash
zstdcat result/sd-image/nixos-sd-image-*.img.zstd | sudo dd of=/dev/mmcblkX bs=4M status=progress
```

## Ref.

* [Work from Ryan Yin](https://github.com/ryan4yin/nixos-rk3588)

## Note:

* Image is able to build from my OPI-5B, might work on x86_64 machine (with binfmt supported).

