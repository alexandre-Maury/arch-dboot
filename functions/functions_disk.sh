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

manage_disk_and_partitions() {

    local disk="$1"
    

    # Vérifier si le disque existe
    if [[ ! -b "/dev/$disk" ]]; then
        log_prompt "ERROR" && echo "Le disque /dev/$disk n'existe pas."
        exit 1
    fi

    # Récupérer le préfixe des partitions (p pour /dev/sdX, rien pour /dev/nvmeXnY)
    local partition_prefix=$(get_disk_prefix "$disk")
    local partition_num=$(lsblk -n -o NAME "/dev/$disk" | grep -E "$(basename "/dev/$disk")[0-9]+" | wc -l)

    # Lister les espaces libres disponibles
    local available_spaces=$(parted "/dev/$disk" unit MiB print free | awk '/Free Space/ {print NR": Start="$1", End="$2", Size="$3}')
    if [[ -z "$available_spaces" ]]; then
        log_prompt "ERROR" && echo "Aucun espace libre détecté sur /dev/$disk."
        exit 1
    fi

    # Demander à l'utilisateur de sélectionner une plage d'espace libre
    log_prompt "INFO" && echo "Liste des espaces libres disponibles :"
    echo
    echo "$available_spaces" | awk -F'[:,]' '{print $1 " - Espace disponible : " $NF}'
    echo
    read -p "Veuillez entrer le numéro de la plage d'espace libre à utiliser : " space_choice

    local selected_space=$(echo "$available_spaces" | grep "^${space_choice}:")
    if [[ -z "$selected_space" ]]; then
        log_prompt "ERROR" && echo "Choix invalide. Veuillez réessayer."
        exit 1
    fi

    # Extraire les limites de la plage sélectionnée
    local start=$(echo "$selected_space" | sed -n 's/.*Start=\([0-9.]*\)MiB.*/\1/p')
    local end_space=$(echo "$selected_space" | sed -n 's/.*End=\([0-9.]*\)MiB.*/\1/p')
    local total=$(echo "$selected_space" | sed -n 's/.*Size=\([0-9.]*\)MiB.*/\1/p')

    if [[ $total -le 0 ]]; then
        log_prompt "ERROR" && echo "L'espace sélectionné est insuffisant pour créer des partitions."
        exit 1
    fi

    # Création des partitions à partir de la liste définie
    partition_num=$(($partition_num + 1))
    for part in "${PARTITIONS_CREATE[@]}"; do
        IFS=':' read -r name size type <<< "$part"
        local device="/dev/${disk}${partition_prefix}${partition_num}"
        
        # Calculer les tailles de partitions
        local end
        if [[ "$size" == "100%" ]]; then
            end="$end_space"
        else
            local size_mib=$(convert_to_mib "$size")
            end=$(bc <<< "$start + $size_mib")
        fi

        if (( $(bc <<< "$end > $end_space") )); then
            log_prompt "ERROR" && echo "Pas assez d'espace pour créer la partition '$name'."
            exit 1
        fi

        # Créer la partition
        parted --script -a optimal /dev/$disk mkpart primary "$type" "${start}MiB" "${end}MiB"

        # Configurer et formater la partition
        case "$name" in
            "boot")
                parted --script /dev/$disk set "$partition_num" esp on
                mkfs.vfat -F32 -n "$name" "$device"
                ;;
            "swap")
                mkswap -L "$name" "$device" && swapon "$device"
                ;;
            "root")
                mkfs.btrfs -f -L "$name" "$device"
                ;;
        esac

        start="$end"
        ((partition_num++))
    done

    # Monter les partitions en fonction des labels
    local partitions=($(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}\([0-9]*\)$/${disk}\1/p"))
    for part in "${partitions[@]}"; do
        local label=$(lsblk "/dev/$part" -n -o LABEL)
        case "$label" in
            "root")
                mount "/dev/$part" "${MOUNT_POINT}"
                for subvol in "${BTRFS_SUBVOLUMES[@]}"; do
                    btrfs subvolume create "${MOUNT_POINT}/${subvol}"
                done
                umount "${MOUNT_POINT}"
                mount -o "${BTRFS_MOUNT_OPTIONS},subvol=@" "/dev/$part" "${MOUNT_POINT}"

                # Monter les autres sous-volumes
                declare -A mount_points=(
                    ["@home"]="${MOUNT_POINT}/home"
                    ["@srv"]="${MOUNT_POINT}/srv"
                    ["@log"]="${MOUNT_POINT}/var/log"
                    ["@cache"]="${MOUNT_POINT}/var/cache"
                    ["@tmp"]="${MOUNT_POINT}/tmp"
                    ["@snapshots"]="${MOUNT_POINT}/snapshots"
                )

                for subvol in "${!mount_points[@]}"; do
                    mkdir -p "${mount_points[$subvol]}"
                    mount -o "${BTRFS_MOUNT_OPTIONS},subvol=$subvol" "/dev/$part" "${mount_points[$subvol]}"
                done

                ;;
            "boot")
                mkdir -p "${MOUNT_POINT}/boot"
                mount "/dev/$part" "${MOUNT_POINT}/boot"
                ;;
        esac
    done
}


windows_part() {

    local partition_boot_windows="$2"

    mkdir -p "${MOUNT_POINT}/win"
    mount /dev/$partition_boot_windows ${MOUNT_POINT}/win
    cp -rf ${MOUNT_POINT}/win/EFI/Microsoft ${MOUNT_POINT}/boot/EFI
}
