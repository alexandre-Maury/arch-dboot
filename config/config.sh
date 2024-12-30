#!/bin/bash

# script config.sh

##############################################################################
## Toute modification incorrecte peut entraîner des perturbations lors de l'installation                                                             
##############################################################################

ZONE="Europe"
PAYS="France"
CITY="Paris"
LANG="fr_FR.UTF-8"
LOCALE="fr_FR"
KEYMAP="fr"
HOSTNAME="archlinux-alexandre"
SSH_PORT=2222  # Remplacez 2222 par le port que vous souhaitez utiliser

MOUNT_POINT="/mnt" # Point de montage    

DEFAULT_BOOT_TYPE="fat32"
DEFAULT_SWAP_TYPE="linux-swap"
DEFAULT_FS_TYPE="btrfs"

DEFAULT_BOOT_SIZE="512MiB"
DEFAULT_SWAP_SIZE="8GiB"
DEFAULT_FS_SIZE="100%"

PARTITIONS_CREATE=(
    "boot:${DEFAULT_BOOT_SIZE}:${DEFAULT_BOOT_TYPE}"
    "swap:${DEFAULT_SWAP_SIZE}:${DEFAULT_SWAP_TYPE}"
    "root:${DEFAULT_FS_SIZE}:${DEFAULT_FS_TYPE}"
)


BOOTLOADER="systemd-boot"  # Utilisation de systemd-boot pour UEFI

# Liste des sous-volumes BTRFS à créer
BTRFS_SUBVOLUMES=("@" "@root" "@home" "@srv" "@log" "@cache" "@tmp" "@snapshots")

# Options de montage BTRFS par défaut
BTRFS_MOUNT_OPTIONS="defaults,noatime,compress=zstd,commit=120"




