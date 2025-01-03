#!/bin/bash

# script test.sh


test() {

    clear

    local disk="$1"
    local partition_boot_windows="$2"

    local partitions=($(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}\([0-9]*\)$/${disk}\1/p"))
    
    for part in "${partitions[@]}"; do

        local label=$(lsblk "/dev/$part" -n -o LABEL)
        local fs_type=$(lsblk "/dev/$part" -n -o FS_TYPE)

        echo "type de la partition $fs_type"
        
    done
}