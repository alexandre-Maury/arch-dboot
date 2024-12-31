#!/bin/bash

# script functions_disk.sh

# Convertit les tailles en MiB
convert_to_mib() {
    local size="$1"
    case "$size" in
        *"GiB"|*"G") 
            echo "$size" | sed 's/[GiB|G]//' | awk '{print $1 * 1024}'
            ;;
        *"MiB"|*"M")
            echo "$size" | sed 's/[MiB|M]//'
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

    DISK="$1"
    DISK_PATH="/dev/$DISK"

    if [[ ! -b "$DISK_PATH" ]]; then
        echo "Le disque $DISK_PATH n'existe pas."
        exit 1
    fi

    # Affiche les partitions existantes pour confirmation
    echo "Voici les partitions actuelles sur $DISK_PATH :"
    lsblk "$DISK_PATH"
    read -p "Êtes-vous sûr de vouloir continuer sans modifier les partitions existantes ? (oui/non) : " CONFIRM
    if [[ "$CONFIRM" != "oui" ]]; then
        echo "Abandon."
        exit 1
    fi

    # Vérifie l'espace non alloué
    FREE_SPACE=$(parted "$DISK_PATH" unit MiB print free | awk '/Free Space/ {print $2, $3}' | tail -n1)
    FREE_START=$(echo "$FREE_SPACE" | awk '{print $1}' | tr -d 'MiB')
    FREE_END=$(echo "$FREE_SPACE" | awk '{print $2}' | tr -d 'MiB')

    if [[ -z "$FREE_START" || -z "$FREE_END" || "$FREE_START" == "$FREE_END" ]]; then
        echo "Aucun espace non alloué disponible sur $DISK_PATH."
        exit 1
    fi

    # Calcule les tailles des partitions
    read -p "Taille de la partition boot (en MiB, par défaut 512) : " BOOT_SIZE
    BOOT_SIZE=${BOOT_SIZE:-512}  # Valeur par défaut : 512 MiB

    read -p "Taille de la partition swap (en MiB, par défaut 4096) : " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-4096}  # Valeur par défaut : 4096 MiB

    # Le reste pour la partition root
    ROOT_SIZE=$((FREE_END - FREE_START - BOOT_SIZE - SWAP_SIZE))  

    if [[ $ROOT_SIZE -le 0 ]]; then
        echo "L'espace non alloué est insuffisant pour créer les partitions."
        exit 1
    fi

    # Crée la partition boot
    echo "Création de la partition boot..."
    parted --script "$DISK_PATH" mkpart primary fat32 "${FREE_START}MiB" "$((FREE_START + BOOT_SIZE))MiB"
    parted --script "$DISK_PATH" set 1 esp on

    # Crée la partition swap
    echo "Création de la partition swap..."
    parted --script "$DISK_PATH" mkpart primary linux-swap "$((FREE_START + BOOT_SIZE))MiB" "$((FREE_START + BOOT_SIZE + SWAP_SIZE))MiB"

    # Crée la partition root
    echo "Création de la partition root..."
    parted --script "$DISK_PATH" mkpart primary btrfs "$((FREE_START + BOOT_SIZE + SWAP_SIZE))MiB" "${FREE_END}MiB"

    # Formate les partitions
    BOOT_PART="${DISK_PATH}$(lsblk -n -o NAME "$DISK_PATH" | grep -E '^.*1$')"
    SWAP_PART="${DISK_PATH}$(lsblk -n -o NAME "$DISK_PATH" | grep -E '^.*2$')"
    ROOT_PART="${DISK_PATH}$(lsblk -n -o NAME "$DISK_PATH" | grep -E '^.*3$')"

    echo "Formatage de la partition boot en vfat..."
    mkfs.vfat "$BOOT_PART"

    echo "Activation de la partition swap..."
    mkswap "$SWAP_PART"
    swapon "$SWAP_PART"

    echo "Formatage de la partition root en btrfs..."
    mkfs.btrfs "$ROOT_PART"

    # Affiche les résultats finaux
    echo "Partitionnement terminé avec succès !"
    lsblk "$DISK_PATH"

    echo "Résumé des partitions :"
    echo "Partition boot : $BOOT_PART (512 MiB, vfat)"
    echo "Partition swap : $SWAP_PART (4 GiB, swap activé)"
    echo "Partition root : $ROOT_PART (btrfs, reste de l'espace disponible)"

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