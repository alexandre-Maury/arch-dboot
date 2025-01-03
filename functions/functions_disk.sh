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


manage_partitions() {

    local disk="$1"
    local dboot="$2"
    local partition_create=()
    local partition_prefix=$(get_disk_prefix "$disk")
    local partition_num=0

    # Vérifier si le disque existe
    if [[ ! -b "/dev/$disk" ]]; then
        log_prompt "ERROR" && echo "Le disque /dev/$disk n'existe pas."
        exit 1
    fi

    if [[ "$dboot" == "True" ]]; then

        partition_num=$(lsblk -n -o NAME "/dev/$disk" | grep -E "$(basename "/dev/$disk")[0-9]+" | wc -l)

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

    else

        parted --script /dev/$disk mklabel gpt

        local start="1MiB"
        local disk_size=$(lsblk "/dev/$disk" -b -o SIZE | tail -n 1)  # Taille en octets
        local end_space=$((disk_size / 1024 / 1024))  # Conversion en MiB
    fi

    while true; do
        # Réinitialiser le tableau des partitions
        partition_create=()

        # Boucle pour demander les informations à l'utilisateur
        while true; do
            
            clear
            log_prompt "INFO" && echo "Partitions définies :"
            echo
            echo "----------------------------------------"
            printf "%-15s %-10s %-10s\n" "PARTITION" "TAILLE" "TYPE FS"
            echo "----------------------------------------"
            echo
            for partition in "${partition_create[@]}"; do
                IFS=':' read -r partition_name partition_size partition_type <<< "$partition"
                printf "%-15s %-10s %-10s\n" "$partition_name" "$partition_size" "$partition_type"
            done
            echo
            echo "----------------------------------------"
            echo
            echo
            log_prompt "INFO" && echo "Création d'une nouvelle partition :"
            echo
            read -p "Nom de la partition à créer (ex. swap, root, home, boot) : " partition_name
            if [[ -z "$partition_name" ]]; then
                log_prompt "ERROR" && echo "Nom invalide. Veuillez réessayer."
                continue
            fi

            clear
            echo
            echo "Taille de la partition : "
            echo
            echo "ex. "
            echo "Vous souhaiter une partition de 1GiB saisir : 1024MiB "
            echo "Pour convertir une valeur donnée en GiB (gibioctets) en MiB (mebioctets), il suffit de multiplier par 1024."
            echo "Vous souhaiter que la partition occupe l'espace restante saisir : 100% "
            echo
            read -p "Votre Choix (par défaut : 1024) : " partition_size
            partition_size="${partition_size:-1024}"

            clear
            echo
            echo "Types disponibles pour la partition $partition_name:"
            echo
            local index=1
            for type in "${PARTITIONS_TYPE[@]}"; do
                echo "$index. $type"
                ((index++))
            done
            echo
            read -p "Choisissez un type de fichier : " partition_type
            case "$partition_type" in
                "1"|"swap")
                    partition_type="linux-swap"
                    ;;
                "2"|"ext4"|"")
                    partition_type="ext4"
                    ;;
                "3"|"btrfs")
                    partition_type="btrfs"
                    ;;
                "4"|"fat32")
                    partition_type="fat32"
                    ;;
                *)
                    echo "Type inconnu, veuillez réessayer."
                    continue
                    ;;
            esac

            # Ajouter la partition au tableau
            partition_create+=("${partition_name}:${partition_size}:${partition_type}")

            clear
            echo
            # Demander si l'utilisateur souhaite ajouter une autre partition
            read -p "Voulez-vous ajouter une autre partition ? (y/N) : " continue_choice
            [[ "$continue_choice" =~ ^[Yy]$ ]] || break
        done

        # Vérification des partitions avant la création
        clear
        log_prompt "INFO" && echo "Partitions définies :"
        echo
        echo "----------------------------------------"
        printf "%-15s %-10s %-10s\n" "PARTITION" "TAILLE" "TYPE FS"
        echo "----------------------------------------"
        echo
        for partition in "${partition_create[@]}"; do
            IFS=':' read -r partition_name partition_size partition_type <<< "$partition"
            printf "%-15s %-10s %-10s\n" "$partition_name" "$partition_size" "$partition_type"
        done
        echo
        echo "----------------------------------------"
        echo
        read -p "Les partitions sont-elles correctes ? (y/N) : " confirm_choice
        if [[ "$confirm_choice" =~ ^[Yy]$ ]]; then
            break # Sortir de la boucle principale si les partitions sont correctes
        fi
        echo
        # Si l'utilisateur veut recommencer
        log_prompt "INFO" && echo "Recommençons la sélection des partitions."
    done

    partition_num=$(($partition_num + 1))

    for part in "${partition_create[@]}"; do

        IFS=':' read -r name size type <<< "$part"

        local device="/dev/${disk}${partition_prefix}${partition_num}"
        
        # Calculer les tailles de partitions
        local end
        if [[ "$size" == "100%" ]]; then
            end="$end_space"
        else

            local start_mib=$(convert_to_mib "$start")
            local size_mib=$(convert_to_mib "$size")

            end=$(bc <<< "$start_mib + $size_mib")

        fi

        if (( $(bc <<< "$end > $end_space") )); then
            log_prompt "ERROR" && echo "Pas assez d'espace pour créer la partition '$name'."
            exit 1
        fi

        # Créer la partition
        parted --script -a optimal /dev/$disk mkpart primary "$type" "${start}MiB" "${end}MiB"

        # formater la partition : pour plus de choix ajouter ici ex. ext4, xfs ...
        case "$type" in
            "fat32")
                parted --script /dev/$disk set "$partition_num" esp on
                parted --script /dev/$disk set "$partition_num" boot on

                mkfs.vfat -F32 -n "$name" "$device"
                ;;
            "linux-swap")
                parted --script /dev/$disk set "$partition_num" swap on
                mkswap -L "$name" "$device" && swapon "$device"
                ;;
            "btrfs")
                mkfs.btrfs -f -L "$name" "$device"
                ;;
            "ext4")
                mkfs.ext4 -L "$name" "$device"
                ;;

            *)
                echo "Type de partition inconnu ou non pris en charge : $type"
                echo "Aucune action n'a été effectuée pour la partition : $device."
                ;;
        esac

        start="$end"
        end_space=$(($end_space - $end))
        ((partition_num++))
        
    done
}

mount_partitions () {

    local disk="$1"
    local partitions=($(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}\([0-9]*\)$/${disk}\1/p"))
    
    for part in "${partitions[@]}"; do

        local label=$(lsblk "/dev/$part" -n -o LABEL)
        local fs_type=$(lsblk "/dev/$part" -n -o FSTYPE)

        echo "Préparation de la partition $part en : $fs_type"

        # Configurer et formater la partition
        case "$fs_type" in
            "vfat")
                # Montage de la partition vfat (par exemple, pour /boot/efi)
                mount --mkdir "/dev/$part" "${MOUNT_POINT}/boot"
                ;;
            "btrfs")
                # Création et montage des sous-volumes pour btrfs
                mount --mkdir "/dev/$part" "${MOUNT_POINT}"

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
            "ext4")
                # Montage de la partition ext4
                if [[ "$label" == "root" ]]; then
                    mount --mkdir "/dev/$part" "${MOUNT_POINT}"
                else
                    # Montage d'une partition ext4
                    mount --mkdir "/dev/$part" "${MOUNT_POINT}/$label"
                fi
                ;;

            *)
                echo "Type de partition inconnu ou non pris en charge : $fs_type"
                echo "Aucune action n'a été effectuée pour la partition /dev/$part."
                ;;

        esac

    done

}