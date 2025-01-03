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

PARTITIONS_TYPE=(
    "swap"
    "ext4"
    "btrfs"
    "fat32"
)


BOOTLOADER="systemd-boot"  # Utilisation de systemd-boot pour UEFI

# Liste des sous-volumes BTRFS à créer
BTRFS_SUBVOLUMES=("@" "@root" "@home" "@srv" "@log" "@cache" "@tmp" "@snapshots")

# Options de montage BTRFS par défaut
BTRFS_MOUNT_OPTIONS="defaults,noatime,compress=zstd,commit=120"




