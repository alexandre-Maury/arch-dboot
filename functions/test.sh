#!/bin/bash


test_disk() {

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

    # Afficher le résumé
    log_prompt "INFO" && echo "Création des partitions sur /dev/$disk :"
    echo
    printf "%-10s %-10s %-10s\n" "Partition" "Taille" "Type"
    echo "--------------------------------"
    for part in "${PARTITIONS_CREATE[@]}"; do
        IFS=':' read -r name size type <<< "$part"
        printf "%-10s %-10s %-10s\n" "$name" "$size" "$type"
    done
    echo

    echo "Vous pouvez modifier le fichier config.sh pour adapter la configuration selon vos besoins."
    echo
    read -rp "Continuer ? (y/n): " confirm
    [[ "$confirm" != [yY] ]] && exit 1
    echo

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
    end=$(echo "$selected_space" | sed -n 's/.*End=\([0-9.]*\)MiB.*/\1/p')
    total=$(echo "$selected_space" | sed -n 's/.*Size=\([0-9.]*\)MiB.*/\1/p')

    if [[ $total -le 0 ]]; then
        log_prompt "ERROR" && echo "L'espace sélectionné est insuffisant pour créer des partitions."
        exit 1
    fi

    log_prompt "INFO" && echo "Espace total disponible dans la plage sélectionnée : ${total} MiB"

        # Créer chaque partition
    for part in "${PARTITIONS_CREATE[@]}"; do
        IFS=':' read -r name size type <<< "$part"
        local device="/dev/${disk}${partition_prefix}${partition_num}"
        local end=$([ "$size" = "100%" ] && echo "100%" || echo "$(convert_to_mib "$size")MiB")

        # Créer la partition
        parted --script -a optimal /dev/$disk mkpart primary "$start" "$end"

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

        start="$end"
        ((partition_num++))
    done

    echo "Partitionnement terminé avec succès"

    # # Lecture des tailles de partitions
    # read -p "Taille de la partition boot (en MiB, par défaut 512) : " boot_size
    # boot_size=${boot_size:-512}

    # read -p "Taille de la partition swap (en MiB, par défaut 4096) : " swap_size
    # swap_size=${swap_size:-4096}

    # # Calcul de la partition root
    # root_size=$((total - boot_size - swap_size))

    # Le numéro de la nouvelle partition est part_count + 1
    # BOOT_PART_NUM=$((part_count + 1))
    # SWAP_PART_NUM=$((part_count + 2))

    # # Création de la partition boot
    # echo "Création de la partition boot..."
    # parted --script "/dev/$disk" mkpart primary fat32 "${start}MiB" "$((start + boot_size))MiB"

    # # Activation de l'attribut ESP sur la nouvelle partition boot
    # echo "Activation de l'attribut ESP sur la partition boot (partition numéro $BOOT_PART_NUM)..."
    # parted --script "/dev/$disk" set "$BOOT_PART_NUM" esp on

    # echo "Création de la partition swap..."
    # parted --script "/dev/$disk" mkpart primary linux-swap "$((start + boot_size))MiB" "$((start + boot_size + swap_size))MiB"
    # parted --script "/dev/$disk" set "$SWAP_PART_NUM" swap on

    # echo "Création de la partition root..."
    # parted --script "/dev/$disk" mkpart primary ext4 "$((start + boot_size + swap_size))MiB" "$end"MiB

}