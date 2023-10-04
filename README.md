# NixOS build for Orangepi 5B

## Overview

Build the installer image which is ready to flash to SDCard to boot.
The final image contains also the `u-boot-rockchip.bin` flashed.

To build the image, try `nix build`, to flash to sdcard, try `nix run . -- /dev/mmcblk1`

## Spec

* Kernel 5.10.160 from [Armbian](https://github.com/armbian/linux-rockchip)
* U-boot - mainline 2023-07-02 with patch
* Panfork (for mesa 3D) v20.0.0 + mali firmware

Check `flake.nix` for more detail.

## Flash the image

```bash
zstdcat result/sd-image/nixos-sd-image-*.img.zstd | sudo dd of=/dev/mmcblkX bs=4M status=progress
```

## Status

### Working

* Onchip IPs seem to work
* Ethernet
* GPU - on wayland (the `swaywm` included within sdcard image)
  * Start `sway` will then load Mali firmware, to check GPU accelleration, run firefox with Wayland enable `MOZ_ENABLE_WAYLAND=1 firefox`
    * `about:support` will show the status of GPU supporting
  * Perf is quite good - video playback consumed ~30% CPU (1080p youtube video on 4K monitor), ~50% CPU (4K youtube video on 4K monitor) - fullscreen mode
* USB-C OTG-mode
* Other? - not fully check (not that intrrested in :D)
* Audio

### Not working

* Wifi/BT
* Other??

## Ref.

* [Work from Ryan Yin](https://github.com/ryan4yin/nixos-rk3588)

## Note:

* Image is able to build from my OPI-5B, might work on x86_64 machine (with binfmt supported).

