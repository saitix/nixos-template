# Managed by partition-disk.sh — mounts by filesystem LABEL so this config
# works on any disk without hardcoded UUIDs.
# Do NOT add UUIDs back here; if you repartition, re-run partition-disk.sh.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-label/root";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  # No swap partition by design (512M ESP + rest for /). Add a swapfile
  # later if needed.

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
