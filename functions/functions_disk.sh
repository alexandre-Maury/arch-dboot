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
    local partition_prefix=$(get_disk_prefix "$disk")
    local partition_num=0

    # Vérifier si le disque existe
    if [[ ! -b "/dev/$disk" ]]; then
        log_prompt "ERROR" && echo "Le disque /dev/$disk n'existe pas."
        exit 1
    fi

    while true; do
        clear
        echo
        echo "====================================================="
        echo "   Choisissez le mode de configuration des partitions"
        echo "====================================================="
        echo
        echo "1. Mode Standard (valeurs par défaut)"
        echo
        echo "   - Les partitions seront créées en fonction des valeurs par défaut définies dans le fichier config.sh."
        echo "   - Le double boot n'est PAS activé dans ce mode."
        echo
        echo "2. Mode Avancé (configuration manuelle)"
        echo
        echo "   - Vous pouvez configurer les partitions selon vos besoins, dans la limite des contraintes du programme."
        if [[ "$dboot" == "True" ]]; then
            echo "   - Le double boot est possible dans ce mode."
        fi
        echo
        echo "====================================================="
        echo
        read -p "Veuillez saisir votre choix (1 ou 2) : " choice_mode

        case "$choice_mode" in
            1)
                mode_partitions="mode_standard"
                dboot=False
                break
                ;;
            2)
                mode_partitions="mode_avance"
                echo

                if [[ "$dboot" == "True" ]]; then

                    log_prompt "INFO" && read -p "Souhaitez-vous procéder à un Dual Boot ? (y/N) : " dual_boot
                    echo
                    if [[ "$dual_boot" =~ ^[Yy]$ ]]; then

                        echo "====================================================="
                        echo "            Configuration pour un Dual Boot"
                        echo "====================================================="
                        echo
                        echo "⚠️ Vous avez choisi de procéder à une installation en Dual Boot."
                        echo
                        echo "Avant de continuer, assurez-vous d'avoir préparé les partitions nécessaires."
                        echo "Voici les étapes à suivre :"
                        echo
                        echo "1️⃣ Création de la partition '/EFI' :"
                        echo "   - Cette partition doit être créée avant l'installation de Windows."
                        echo "   - Utilisez l'outil de votre choix, comme le live CD d'Arch Linux avec 'cfdisk'."
                        echo "     ➡️ Commande recommandée : cfdisk /dev/sda"
                        echo "   - Assurez-vous de définir le type de partition sur 'EFI System Partition' (ESP)."
                        echo "   - Taille minimale requise : 512 Mo."
                        echo "   - Prenez note du chemin de cette partition (par exemple, /dev/sda1)."
                        echo "   - Cette partition sera utilisée par le bootloader lors de l'installation d'Arch Linux."
                        echo
                        echo "2️⃣ Création de la partition '/root' :"
                        echo "   - Réduisez la taille d'une partition existante pour libérer de l'espace."
                        echo "   - La nouvelle partition 'root' sera utilisée pour le système Arch Linux."
                        echo "   - Vous pouvez utiliser des outils de partitionnement pour redimensionner les partitions."
                        echo
                        echo "⚠️ Remarque importante :"
                        echo "   Soyez extrêmement prudent lors du redimensionnement des partitions existantes."
                        echo "   Une mauvaise manipulation peut entraîner une perte de données."
                        echo "   Assurez-vous d'avoir effectué une sauvegarde complète de vos données avant de continuer."
                        echo
                        echo "====================================================="
                        echo
                        log_prompt "INFO" && read -p "Avez-vous bien préparé vos partitions ? (y/N) : " choice_boot

                        if [[ ! "$choice_boot" =~ ^[Yy]$ ]]; then
                            echo
                            log_prompt "ERROR" && echo "Installation annulé par l'utilisateur."
                            echo
                            exit 1
                        fi

                    else
                        dboot=False
                    fi

                fi


                break
                ;;

            *)
                echo "Choix invalide, veuillez réessayer."
                ;;
        esac
    done

    if [[ "$dboot" == "True" && "$mode_partitions" == "mode_avance" ]]; then

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
        local end_space=$(echo "$selected_space" | awk '/End=/ {match($0, /End=([0-9.]+)MiB/, a); print a[1] - 1}')
        local total=$(echo "$selected_space" | sed -n 's/.*Size=\([0-9.]*\)MiB.*/\1/p')

    else

        parted --script /dev/$disk mklabel gpt

        local available_spaces=$(parted "/dev/$disk" unit MiB print free | awk '/Free Space/ {print " Start="$1", End="$2", Size="$3}')

        local start=1
        local end_space=$(echo "$available_spaces" | awk '/End=/ {match($0, /End=([0-9.]+)MiB/, a); print a[1] - 1}')
        local total=$(echo "$available_spaces" | sed -n 's/.*Size=\([0-9.]*\)MiB.*/\1/p')

    fi

    if [[ $total -le 0 ]]; then
        log_prompt "ERROR" && echo "L'espace sélectionné est insuffisant pour créer des partitions."
        exit 1
    fi



    if [[ "$mode_partitions" == "mode_avance" ]]; then

        # boucle pour reset le tableau si l'utilisateur souhaite recommancer
        while true; do

            # Réinitialiser le tableau des partitions
            PARTITIONS_CREATE=()
            disk_size="$total"

            # Boucle pour demander l'ensembles des informations à l'utilisateur pour la création des partitions
            while true; do
                clear
                # boucle pour la saisi du nom de la partition
                while true; do
                    clear
                    echo
                    echo "Total Disponible : $total MiB"
                    echo "Total Restant :    $disk_size MiB"
                    echo
                    log_prompt "INFO" && echo "Partitions définies : ${#PARTITIONS_CREATE[@]}" 
                    echo
                    echo "----------------------------------------"
                    printf "%-15s %-10s %-10s\n" "PARTITION" "TAILLE" "TYPE FS"
                    echo "----------------------------------------"
                    echo
                    for partition in "${PARTITIONS_CREATE[@]}"; do
                        IFS=':' read -r partition_name partition_size partition_type <<< "$partition"
                        printf "%-15s %-10s %-10s\n" "$partition_name" "$partition_size" "$partition_type"
                    done
                    echo
                    echo "----------------------------------------"
                    echo
                    echo
                    echo
                    log_prompt "INFO" && echo "Création d'une nouvelle partition :"
                    echo
                    # Message d'erreur
                    if [[ -n "$part_error" ]]; then
                        log_prompt "ERROR" && echo $part_error
                    fi

                    echo
                    echo "Voici les partitions recommandées à créer pour une installation réussie :"
                    echo
                    echo "1. Partition Boot (EFI)"
                    echo "   - Type : fat32"
                    echo "   - Taille recommandée : 512MiB"
                    echo "   - Nom recommandé : [boot] (obligatoire pour l'exécution correcte de l'installation)"
                    echo
                    echo "2. Partition Swap"
                    echo "   - Type : linux-swap"
                    echo "   - Taille recommandée : selon vos besoins (ex. 2 à 4GiB pour la plupart des cas)"
                    echo "   - Nom recommandé : [swap]"
                    echo
                    echo "3. Partition Racine (OBLIGATOIRE)"
                    echo "   - Deux options disponibles :"
                    echo "     a. Type : btrfs"
                    echo "        - Subvolumes (modifiable dans config.sh) : '@' '@root' '@home' '@srv' '@log' '@cache' '@tmp' '@snapshots'"
                    echo "        - Taille recommandée : 100% (pour occuper tout l'espace restant)"
                    echo "     b. Type : ext4"
                    echo "        - Taille recommandée : selon vos besoins (ex. 20-50GiB pour la racine)"
                    echo "   - Nom recommandé : [root] (obligatoire pour l'exécution correcte de l'installation)"
                    echo
                    echo "4. Partition Home (Facultative)"
                    echo "   - Type : ext4"
                    echo "   - Taille recommandée : selon vos besoins"
                    echo "   - Nom recommandé : [home]"
                    echo

                    read -p "Nom de la partition à créer (ex. boot, swap, root, home) : " partition_name
                    partition_name=$(echo "$partition_name" | tr '[:upper:]' '[:lower:]') # Conversion en minuscule

                    case $partition_name in
                        boot)
                            echo "Création de la partition Boot..."
                            echo "Type : fat32"
                            echo "Taille recommandée : 512MiB"
                            echo "Assurez-vous de sélectionner une partition EFI System Partition (ESP) dans l'outil de partitionnement."
                            part_error=""
                            break # Sortir de la boucle si le nom est valide
                            ;;
                        swap)
                            echo "Création de la partition Swap..."
                            echo "Type : linux-swap"
                            echo "Taille recommandée : selon vos besoins (ex. 2-4GiB)"
                            part_error=""
                            break # Sortir de la boucle si le nom est valide
                            ;;
                        root)
                            echo "Création de la partition Racine..."
                            echo "Type recommandé : btrfs ou ext4"
                            echo "Si vous choisissez btrfs, configurez les subvolumes selon config.sh."
                            echo "Taille recommandée : 100% pour btrfs ou selon vos besoins pour ext4 (ex. 20-50GiB)"
                            part_error=""
                            break # Sortir de la boucle si le nom est valide
                            ;;
                        home)
                            echo "Création de la partition Home..."
                            echo "Type : ext4"
                            echo "Taille recommandée : selon vos besoins"
                            part_error=""
                            break # Sortir de la boucle si le nom est valide
                            ;;
                        *)
                            part_error="Nom de partition : $partition_name non valide. Veuillez choisir parmi [boot, swap, root, home]."
                            ;;
                    esac
                done


                clear
                echo
                echo "Taille de la partition : $partition_name"
                echo
                echo "ex. "
                echo "Vous souhaiter une partition de 1GiB saisir : 1024MiB ou 1GiB"
                echo "Vous souhaiter que la partition occupe l'espace restante saisir : 100% "
                echo
                read -p "Votre Choix (unité obligatoire ex. [ MiB | GiB ] ou [ % ] ) : " partition_size
                partition_size="${partition_size}"

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
                PARTITIONS_CREATE+=("${partition_name}:${partition_size}:${partition_type}")

                clear
                echo

                [[ "$partition_size" != "100%" ]] || break

                # Demander si l'utilisateur souhaite ajouter une autre partition
                read -p "Voulez-vous ajouter une autre partition ? (y/N) : " continue_choice
                [[ "$continue_choice" =~ ^[Yy]$ ]] || break
                
                disk_size=$(($disk_size - $(convert_to_mib "$partition_size")))
            done

            # Vérification des partitions avant la création
            clear
            echo
            log_prompt "INFO" && echo "Partitions définies :"
            echo
            echo "----------------------------------------"
            printf "%-15s %-10s %-10s\n" "PARTITION" "TAILLE" "TYPE FS"
            echo "----------------------------------------"
            echo
            for partition in "${PARTITIONS_CREATE[@]}"; do
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

    else

        # Vérification des partitions avant la création
        clear
        log_prompt "INFO" && echo "Partitions définies dans config.sh:"
        echo
        echo "----------------------------------------"
        printf "%-15s %-10s %-10s\n" "PARTITION" "TAILLE" "TYPE FS"
        echo "----------------------------------------"
        echo
        for partition in "${PARTITIONS_CREATE[@]}"; do
            IFS=':' read -r partition_name partition_size partition_type <<< "$partition"
            printf "%-15s %-10s %-10s\n" "$partition_name" "$partition_size" "$partition_type"
        done
        echo
        echo "----------------------------------------"
        echo
        read -p "Les partitions sont-elles correctes ? (y/N) : " confirm_choice

        if [[ ! "$confirm_choice" =~ ^[Yy]$ ]]; then
            echo "Installation annulée par l'utilisateur."
            exit 1
        fi

        echo

    fi

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
        log_prompt "INFO" && echo "Création de la partition $name - Start ==> $start et End ==> $end"
        parted --script -a optimal /dev/$disk mkpart primary "$type" "${start}MiB" "${end}MiB"

        # formater la partition : pour plus de choix ajouter ici ex. ext4, xfs ...
        case "$type" in
            "fat32")
                parted --script /dev/$disk set "$partition_num" esp on
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
        ((partition_num++))

    done
}

mount_partitions () {

    local disk="$1"
    local partitions=($(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}\([0-9]*\)$/${disk}\1/p"))

    for part in "${partitions[@]}"; do

        local label=$(lsblk "/dev/$part" -n -o LABEL)
        local fs_type=$(lsblk "/dev/$part" -n -o FSTYPE)

        # Configurer et formater la partition
        case "$fs_type" in
            "vfat")  
                if [[ "$label" == "boot" ]]; then
                    local boot_part=$part 
                else
                    local efi_part=$part
                fi

                ;;

            "btrfs") 
                if [[ "$label" == "root" ]]; then
                    local root_part=$part
                    local root_fstype="btrfs"
                fi
                ;;

            "ext4")
                if [[ "$label" == "root" ]]; then
                    local root_part=$part
                    local root_label="ext4"
                else
                    local home_part=$part
                    local home_fstype="ext4"
                fi
                ;;

            *) echo "Partition ignorée: /dev/$part (Label: $label)" ;;

        esac

    done

    # Monter et configurer la partition root avec BTRFS ou EXT4
    if [[ -n "$root_part" ]]; then

        if [[ "$root_fstype" == "btrfs" ]]; then

            echo "Configuration de la partition root (/dev/$root_part)..."
        
            # Montage initial pour création des sous-volumes
            mount --mkdir "/dev/$root_part" "${MOUNT_POINT}"
            
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

        if [[ "$root_fstype" == "ext4" ]]; then
            mount --mkdir "/dev/$root_part" "${MOUNT_POINT}"
        fi
    fi

    # Monter la partition boot
    if [[ -n "$boot_part" ]]; then
        mount --mkdir "/dev/$boot_part" "${MOUNT_POINT}/boot"
    fi

    if [[ -n "$efi_part" ]]; then
        mount --mkdir "/dev/$efi_part" "${MOUNT_POINT}/windows"
        cp -r "${MOUNT_POINT}/windows/EFI/Microsoft" ${MOUNT_POINT}/boot/EFI
    fi

    # Monter la partition home
    if [[ -n "$home_part" ]]; then
        mount --mkdir "/dev/$home_part" "${MOUNT_POINT}/home"
    fi

}