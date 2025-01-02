#!/bin/bash

# script functions_disk.sh

# Convertit les tailles en MiB
convert_to_mib() {
    local size="$1"
    case "$size" in
        *"GiB"|*"G") 
            echo "$size" | sed 's/GiB//;s/G//' | awk '{print $1 * 1024}'
            ;;
        *"MiB"|*"M")
            echo "$size" | sed 's/MiB//;s/M//'
            ;;
        *"%")
            echo "$size"
            ;;
        *)
            echo "0"
            ;;
    esac
}

# Détermine le type de disque
get_disk_prefix() {
    [[ "$1" == nvme* ]] && echo "p" || echo ""
}

# Fonction pour formater l'affichage de la taille d'une partition en GiB ou MiB
format_space() {
    local space=$1
    local space_in_gib

    # Si la taille est supérieur ou égal à 1 Go (1024 MiB), afficher en GiB
    if (( space >= 1024 )); then
        # Convertion en GiB
        space_in_gib=$(echo "scale=2; $space / 1024" | bc)
        echo "${space_in_gib} GiB"
    else
        # Si la taille est inférieur à 1 GiB, afficher en MiB
        echo "${space} MiB"
    fi
}

# Fonction pour afficher les informations des partitions
show_disk_partitions() {
    
    local status="$1"
    local disk="$2"
    local partitions
    local NAME
    local SIZE
    local FSTYPE
    local LABEL
    local MOUNTPOINT
    local UUID


    log_prompt "INFO" && echo "$status" && echo ""
    echo "Device : /dev/$disk"
    echo "Taille : $(lsblk -n -o SIZE "/dev/$disk" | head -1)"
    echo "Type : $(lsblk -n -o TRAN "/dev/$disk")"
    echo -e "\nInformations des partitions :"
    echo "----------------------------------------"
    # En-tête
    printf "%-10s %-10s %-10s %-15s %-15s %s\n" \
        "PARTITION" "TAILLE" "TYPE FS" "LABEL" "POINT MONT." "UUID"
    echo "----------------------------------------"

    while IFS= read -r partition; do
        partitions+=("$partition")
    done < <(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}\([0-9]*\)$/${disk}\1/p")

    # Affiche les informations de chaque partition
    for partition in "${partitions[@]}"; do  # itérer sur le tableau des partitions
        if [ -b "/dev/$partition" ]; then
            # Récupérer chaque colonne séparément pour éviter toute confusion
            NAME=$(lsblk "/dev/$partition" -n -o NAME)
            SIZE=$(lsblk "/dev/$partition" -n -o SIZE)
            FSTYPE=$(lsblk "/dev/$partition" -n -o FSTYPE)
            LABEL=$(lsblk "/dev/$partition" -n -o LABEL)
            MOUNTPOINT=$(lsblk "/dev/$partition" -n -o MOUNTPOINT)
            UUID=$(lsblk "/dev/$partition" -n -o UUID)

            # Gestion des valeurs vides
            NAME=${NAME:-"[vide]"}
            SIZE=${SIZE:-"[vide]"}
            FSTYPE=${FSTYPE:-"[vide]"}
            LABEL=${LABEL:-"[vide]"}
            MOUNTPOINT=${MOUNTPOINT:-"[vide]"}
            UUID=${UUID:-"[vide]"}


            # Affichage formaté
            printf "%-10s %-10s %-10s %-15s %-15s %s\n" "$NAME" "$SIZE" "$FSTYPE" "$LABEL" "$MOUNTPOINT" "$UUID"
            
        fi
    done

    # Résumé
    echo -e "\nRésumé :"
    echo "Nombre de partitions : $(echo "${partitions[@]}" | wc -w)"  
    echo "Espace total : $(lsblk -n -o SIZE "/dev/$disk" | head -1)"

}


# Fonction pour effacer tout le disque
erase_disk() {
    local disk="$1"
    local disk_size
    local mounted_parts
    local swap_parts
    
    # Récupérer les partitions montées (non-swap)
    mounted_parts=$(lsblk "/dev/$disk" -o NAME,MOUNTPOINT -n -l | grep -v "\[SWAP\]" | grep -v "^$disk " | grep -v " $")
    # Liste des partitions swap
    swap_parts=$(lsblk "/dev/$disk" -o NAME,MOUNTPOINT -n -l | grep "\[SWAP\]")
    
    # Gérer les partitions montées (non-swap)
    if [ -n "$mounted_parts" ]; then
        log_prompt "INFO" && echo "ATTENTION: Certaines partitions sont montées :" && echo
        echo "$mounted_parts"
        echo ""
        log_prompt "INFO" && read -p "Voulez-vous les démonter ? (y/n) : " response && echo

        if [[ "$response" =~ ^[yY]$ ]]; then
            while read -r part mountpoint; do
                log_prompt "INFO" && echo "Démontage de /dev/$part" && echo ""
                umount "/dev/$part" 
                if [ $? -ne 0 ]; then
                    log_prompt "ERROR" && echo "Démontage de /dev/$part impossible" && echo
                fi
            done <<< "$mounted_parts"
        else
            log_prompt "WARNING" && echo "Opération annulée" && echo
            return 1
        fi
    fi
    
    # Gérer les partitions swap séparément
    if [ -n "$swap_parts" ]; then
        log_prompt "INFO" && echo "ATTENTION: Certaines partitions swap sont activées :" && echo
        echo "$swap_parts"
        echo
        log_prompt "INFO" && read -p "Voulez-vous les démonter ? (y/n) : " response && echo

        if [[ "$response" =~ ^[yY]$ ]]; then
            while read -r part _; do
                log_prompt "INFO" && echo "Démontage de /dev/$part" && echo
                swapoff "/dev/$part"
                if [ $? -ne 0 ]; then
                    log_prompt "ERROR" && echo "Démontage de /dev/$part impossible" && echo
                fi
            done <<< "$swap_parts"
        else
            log_prompt "WARNING" && echo "Opération annulée" && echo
            return 1
        fi
    fi
    
    echo "ATTENTION: Vous êtes sur le point d'effacer TOUT le disque /dev/$disk"
    echo "Cette opération est IRRÉVERSIBLE !"
    echo "Toutes les données seront DÉFINITIVEMENT PERDUES !"
    echo 
    log_prompt "INFO" && read -p "Êtes-vous vraiment sûr ? (y/n) : " response && echo

    if [[ "$response" =~ ^[yY]$ ]]; then
        log_prompt "INFO" && echo "Effacement du disque /dev/$disk en cours ..." && echo

        # Obtenir la taille exacte du disque en blocs
        disk_size=$(blockdev --getsz "/dev/$disk")
        # Utilisation de dd avec la taille exacte du disque
        dd if=/dev/zero of="/dev/$disk" bs=512 count=$disk_size status=progress
        sync
    else
        log_prompt "WARNING" && echo "Opération annulée" && echo
        return 1
    fi
}

preparation_disk() {

    local disk="$1"
    local partition_prefix=$(get_disk_prefix "$disk")
    local partition_num=$(lsblk -n -o NAME "/dev/$disk" | grep -E "$(basename "/dev/$disk")[0-9]+" | wc -l)

    if [[ ! -b "/dev/$disk" ]]; then
        log_prompt "ERROR" && echo "Le disque /dev/$disk n'existe pas."
        exit 1
    fi

    available_spaces=$(parted "/dev/$disk" unit MiB print free | awk '/Free Space/ {print NR": Start="$1", End="$2", Size="$3}')

    if [[ -z "$available_spaces" ]]; then
        log_prompt "ERROR" && echo "Aucun espace libre détecté sur /dev/$disk."
        exit 1
    fi

    log_prompt "INFO" && echo "Liste des espaces libres disponibles :"
    echo
    echo "$available_spaces" | awk -F'[:,]' '{print $1 " - Espace disponible : " $NF}'
    echo
    read -p "Veuillez entrer le numéro de la plage d'espace libre à utiliser : " space_choice

    selected_space=$(echo "$available_spaces" | grep "^${space_choice}:")
    if [[ -z "$selected_space" ]]; then
        log_prompt "ERROR" && echo "Choix invalide. Veuillez réessayer."
        exit 1
    fi

    start=$(echo "$selected_space" | sed -n 's/.*Start=\([0-9.]*\)MiB.*/\1/p')
    end_space=$(echo "$selected_space" | sed -n 's/.*End=\([0-9.]*\)MiB.*/\1/p')
    total=$(echo "$selected_space" | sed -n 's/.*Size=\([0-9.]*\)MiB.*/\1/p')

    if [[ $total -le 0 ]]; then
        log_prompt "ERROR" && echo "L'espace sélectionné est insuffisant pour créer des partitions."
        exit 1
    fi

    log_prompt "INFO" && echo "Espace total disponible dans la plage sélectionnée : ${total} MiB"

    # Créer chaque partition
    partition_num=$(($partition_num + 1))
    for part in "${PARTITIONS_CREATE[@]}"; do
        IFS=':' read -r name size type <<< "$part"
        local device="/dev/${disk}${partition_prefix}${partition_num}"
        
        if [[ "$size" == "100%" ]]; then
            end="$end_space"  # Pour 100%, la partition occupe tout l'espace restant
        else
            size_mib=$(convert_to_mib "$size")
            end=$(bc <<< "$start + $size_mib")
        fi

        if (( $(bc <<< "$end > $end_space") )); then
            log_prompt "ERROR" && echo "Pas assez d'espace pour créer la partition '$name'."
            exit 1
        fi

        # Créer la partition
        parted --script -a optimal /dev/$disk mkpart primary "$type" "${start}MiB" "${end}MiB"

        # Configurer les flags et formater
        case "$name" in
            "boot")
                parted --script /dev/$disk set "$partition_num" esp on
                mkfs.vfat -F32 -n "$name" "$device"
                ;;
            "swap")
                parted --script /dev/$disk set "$partition_num" swap on
                mkswap -L "$name" "$device" && swapon "$device"
                ;;
            "root")
                mkfs.btrfs -f -L "$name" "$device"
                ;;
        esac

        start="$end"  # Mettre à jour le début pour la prochaine partition
        ((partition_num++))  # Incrémenter le numéro de partition
    done

}

mount_partitions() {
    local disk="$1"
    
    # Récupérer toutes les partitions du disque
    local partitions=($(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}\([0-9]*\)$/${disk}\1/p"))
    
    # Identifier les partitions par leur label
    local root_part="" boot_part="" home_part=""

    for part in "${partitions[@]}"; do
        local label=$(lsblk "/dev/$part" -n -o LABEL)
        case "$label" in
            "root") root_part=$part ;;
            "boot") boot_part=$part ;;
            "swap") continue ;;
            *) echo "Partition ignorée: /dev/$part (Label: $label)" ;;
        esac
    done

    # Monter et configurer la partition root avec BTRFS
    if [[ -n "$root_part" ]]; then
        echo "Configuration de la partition root (/dev/$root_part)..."
        
        # Montage initial pour création des sous-volumes
        mount "/dev/$root_part" "${MOUNT_POINT}"
        
        # Créer les sous-volumes BTRFS
        for subvol in "${BTRFS_SUBVOLUMES[@]}"; do
            btrfs subvolume create "${MOUNT_POINT}/${subvol}"
        done
        
        # Démonter pour remonter avec les sous-volumes
        umount "${MOUNT_POINT}"
        
        # Monter le sous-volume principal
        mount -o "${BTRFS_MOUNT_OPTIONS},subvol=@" "/dev/$root_part" "${MOUNT_POINT}"
        
        # Créer et monter les points de montage pour chaque sous-volume
        declare -A mount_points=(
            ["@root"]="/root"
            ["@home"]="/home"
            ["@srv"]="/srv"
            ["@log"]="/var/log"
            ["@cache"]="/var/cache"
            ["@tmp"]="/tmp"
            ["@snapshots"]="/snapshots"
        )
        
        for subvol in "${!mount_points[@]}"; do
            local mount_point="${MOUNT_POINT}${mount_points[$subvol]}"
            mkdir -p "$mount_point"
            mount -o "${BTRFS_MOUNT_OPTIONS},subvol=${subvol}" "/dev/$root_part" "$mount_point"
        done
    fi

    # Monter la partition boot
    if [[ -n "$boot_part" ]]; then
        echo "Montage de la partition boot (/dev/$boot_part)..."
        mkdir -p "${MOUNT_POINT}/boot"
        mount "/dev/$boot_part" "${MOUNT_POINT}/boot"
    fi
}