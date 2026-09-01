#!/usr/bin/env bash
#
# partition-disk.sh — partition a blank disk for this NixOS/WHMCS template
# and rewrite hardware-configuration.nix to mount by LABEL instead of UUID.
#
# Layout (UEFI, entire disk):
#   partition 1: 512 MiB FAT32 ESP, label BOOT  -> /boot
#   partition 2: rest of disk, ext4, label root -> /
#   (no swap partition — add a swapfile later if needed)
#
# Intended to run from the NixOS minimal installer ISO, with this git repo
# cloned next to the script:
#   sudo ./partition-disk.sh /dev/vda
#
set -euo pipefail

# =========================================================================
# Global variables — tweak the layout here.
# =========================================================================
BOOT_LABEL="BOOT"     # FAT32 label of the ESP -> /boot
ROOT_LABEL="root"     # label of the root filesystem -> /
BOOT_SIZE="512M"      # size of the ESP (sgdisk syntax, e.g. 512M, 1G)
FS_TYPE="ext4"        # root filesystem type: "ext4" or "btrfs"
MOUNTPOINT="/mnt"     # target mountpoint when --mount is used
HW_CONF_NAME="hardware-configuration.nix"  # rewritten in-place next to this script

# Derived below (do not edit):
#   DISK, BOOT_PART, ROOT_PART, HW_CONF, SCRIPT_DIR

usage() {
  echo "Usage: sudo $0 <disk-device> [--yes] [--mount]"
  echo ""
  echo "  <disk-device>  entire disk to wipe, e.g. /dev/vda or /dev/sda"
  echo "  --yes          do not ask for confirmation"
  echo "  --mount        also mount the fresh filesystems under $MOUNTPOINT ($MOUNTPOINT/boot)"
  echo "                 ready for: nixos-install / copying this repo to /mnt/etc/nixos"
  echo ""
  echo "Layout is controlled by the globals at the top of this script:"
  echo "  BOOT_SIZE=$BOOT_SIZE ESP (FAT32, label $BOOT_LABEL) + rest of disk"
  echo "  as $FS_TYPE for / (label $ROOT_LABEL). FS_TYPE can be 'ext4' or 'btrfs'."
  exit 1
}

#Read command-line arguments
[[ $# -ge 1 ]] || usage
DISK="$1"
ASSUME_YES=0
DO_MOUNT=0
for arg in "${@:2}"; do
  case "$arg" in
    --yes)   ASSUME_YES=1 ;;
    --mount) DO_MOUNT=1 ;;
    *)       usage ;;
  esac
done

# --- sanity checks -------------------------------------------------------

case "$FS_TYPE" in
  ext4|btrfs) ;;
  *) echo "ERROR: FS_TYPE must be 'ext4' or 'btrfs' (got '$FS_TYPE')" >&2; exit 1 ;;
esac

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo $0 $DISK)" >&2; exit 1
fi

if [[ ! -b "$DISK" ]]; then
  echo "ERROR: $DISK is not a block device" >&2; exit 1
fi

DISK_BASENAME="$(basename "$DISK")"

# Refuse disks that are mounted anywhere (including the running system).
if lsblk -rn -o NAME,MOUNTPOINT "/dev/$DISK_BASENAME" 2>/dev/null | grep -q '[[:space:]]/'; then
  echo "ERROR: $DISK (or a partition on it) is mounted — refusing to wipe" >&2; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HW_CONF="$SCRIPT_DIR/$HW_CONF_NAME"
if [[ ! -f "$HW_CONF" ]]; then
  echo "ERROR: $HW_CONF not found next to this script" >&2; exit 1
fi

# Partition node naming: /dev/vda -> vda1, /dev/nvme0n1 -> nvme0n1p1
if [[ "$DISK_BASENAME" =~ [0-9]$ ]]; then
  P="p"
else
  P=""
fi
BOOT_PART="${DISK}${P}1"
ROOT_PART="${DISK}${P}2"

# Mount options for / in the generated hardware-configuration.nix.
# btrfs gets the standard optimised set (SSD-aware, zstd-compressed,
# space_cache v2). ext4 needs none.
if [[ "$FS_TYPE" == "btrfs" ]]; then
  ROOTFS_OPTIONS='
      options = [ "noatime" "compress=zstd" "ssd" "space_cache=v2" ];'
else
  ROOTFS_OPTIONS=";"
fi

# --- confirm -------------------------------------------------------------

echo "About to WIPE AND REPARTITION this disk:"
lsblk -d -o NAME,SIZE,TYPE,MODEL "$DISK"
echo ""
echo "Resulting layout: $BOOT_PART ($BOOT_SIZE FAT32, label $BOOT_LABEL -> /boot)"
echo "                  $ROOT_PART (rest, $FS_TYPE,    label $ROOT_LABEL -> /)"
echo ""
if [[ $ASSUME_YES -ne 1 ]]; then
  read -rp "Type YES to continue: " reply
  [[ "$reply" == "YES" ]] || { echo "Aborted."; exit 1; }
fi

# --- partition -----------------------------------------------------------

echo ">> Creating GPT partition table on $DISK"
if command -v sgdisk >/dev/null 2>&1; then
  sgdisk --zap-all "$DISK"
  sgdisk -n "1:0:+$BOOT_SIZE" -t 1:ef00 -c 1:"ESP" "$DISK"
  sgdisk -n 2:0:0           -t 2:8300 -c 2:"$ROOT_LABEL" "$DISK"
else
  echo "ERROR: sgdisk not found (expected on the NixOS installer ISO)" >&2; exit 1
fi

partprobe "$DISK" || true
udevadm settle

# Wait for both partition devices to appear (can lag behind on VMs).
for i in $(seq 1 10); do
  [[ -b "$BOOT_PART" && -b "$ROOT_PART" ]] && break
  sleep 1
done
[[ -b "$BOOT_PART" && -b "$ROOT_PART" ]] || {
  echo "ERROR: partitions $BOOT_PART / $ROOT_PART did not appear" >&2; exit 1;
}

# --- format --------------------------------------------------------------

echo ">> Formatting $BOOT_PART (FAT32, label $BOOT_LABEL)"
wipefs -a "$BOOT_PART" 2>/dev/null || true
mkfs.vfat -F 32 -n "$BOOT_LABEL" "$BOOT_PART"

echo ">> Formatting $ROOT_PART ($FS_TYPE, label $ROOT_LABEL)"
wipefs -a "$ROOT_PART" 2>/dev/null || true
case "$FS_TYPE" in
  ext4)  mkfs.ext4 -q -F -L "$ROOT_LABEL" "$ROOT_PART" ;;
  btrfs) mkfs.btrfs -q -f -L "$ROOT_LABEL" "$ROOT_PART" ;;
esac

udevadm settle

for dev in "$BOOT_LABEL" "$ROOT_LABEL"; do
  if ! ls "/dev/disk/by-label/$dev" >/dev/null 2>&1; then
    echo "ERROR: /dev/disk/by-label/$dev missing after formatting" >&2; exit 1
  fi
done
echo ">> OK: /dev/disk/by-label/{$BOOT_LABEL,$ROOT_LABEL} present"

# --- rewrite hardware-configuration.nix ----------------------------------

echo ">> Rewriting $HW_CONF with LABEL= mounts"
cp -a "$HW_CONF" "$HW_CONF.bak"

cat > "$HW_CONF" <<EOF
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
    { device = "/dev/disk/by-label/$ROOT_LABEL";
      fsType = "$FS_TYPE";
    }$ROOTFS_OPTIONS

  fileSystems."/boot" =
    { device = "/dev/disk/by-label/$BOOT_LABEL";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  # No swap partition by design (\$BOOT_SIZE ESP + rest for /). If you need
  # swap, prefer a swapfile.

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
EOF

# --- optional mount ------------------------------------------------------

if [[ $DO_MOUNT -eq 1 ]]; then
  echo ">> Mounting $ROOT_PART at $MOUNTPOINT and $BOOT_PART at $MOUNTPOINT/boot"
  mount "$ROOT_PART" "$MOUNTPOINT"
  mkdir -p "$MOUNTPOINT/boot"
  mount "$BOOT_PART" "$MOUNTPOINT/boot"
fi

echo ""
echo "Done. Old hardware config saved as hardware-configuration.nix.bak."
echo "Next steps on the installer ISO:"
echo "  1. (if not used --mount) mount /dev/disk/by-label/root /mnt && \\"
echo "        mkdir -p /mnt/boot && mount /dev/disk/by-label/BOOT /mnt/boot"
echo "  2. cp -r $SCRIPT_DIR /mnt/etc/nixos    # or rsync -a --exclude .git"
echo "  3. nixos-install --root /mnt"
echo "  4. commit the rewritten hardware-configuration.nix back to git"
