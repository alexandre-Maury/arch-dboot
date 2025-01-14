#!/bin/bash

# script system.sh

##############################################################################
## Fichier de configuration interne, ne pas modifier                                                           
##############################################################################

## Récupération des disques disponibles    
LIST_DISK="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 

INTERFACE="$(ip link show | awk -F': ' '/^[0-9]+: / && !/lo/ {print $2; exit}')"
MAC_ADDRESS=$(ip link | awk '/ether/ {print $2; exit}')
CPU_COEUR=$(grep -c ^processor /proc/cpuinfo) 
RAM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')  
GPU_VENDOR=$(lspci | grep -i "VGA\|3D" | awk '{print tolower($0)}')
CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')

# Détection du type de processeur
case "$CPU_VENDOR" in
    "GenuineIntel")
        PROC_UCODE="intel-ucode.img"
        ;;
    "AuthenticAMD")
        PROC_UCODE="amd-ucode.img"
        ;;
    *)
        PROC_UCODE=""
        ;;
esac

## détermine le suffixe utilisé pour les partitions d'un disque en fonction de son type (NVMe ou non).
get_disk_prefix() {
    [[ "$1" == nvme* ]] && echo "p" || echo ""
}
















