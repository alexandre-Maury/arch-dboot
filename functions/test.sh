#!/bin/bash


test_disk() {

    disk="$1"

    if [[ ! -b "/dev/$disk" ]]; then
        echo "Le disque /dev/$disk n'existe pas."
        exit 1
    fi

    available_spaces=$(parted "/dev/$disk" unit MiB print free | awk '/Free Space/ {print NR": Start="$1", End="$2", Size="$3}')

    if [[ -z "$available_spaces" ]]; then
        echo "Aucun espace libre détecté sur /dev/$disk."
        exit 1
    fi

    echo "Liste des espaces libres disponibles :"
    echo "$available_spaces" | awk -F'[:,]' '{print $1 " - Espace disponible : " $NF}'

    # Propose à l'utilisateur de choisir un espace libre
    read -p "Veuillez entrer le numéro de la plage d'espace libre à utiliser : " space_choice

    selected_space=$(echo "$available_spaces" | grep "^${space_choice}:")
    if [[ -z "$selected_space" ]]; then
        echo "Choix invalide. Veuillez réessayer."
        exit 1
    fi

    free_start=$(echo "$selected_space" | sed -n 's/.*Start=\([0-9.]*\)MiB.*/\1/p')
    free_end=$(echo "$selected_space" | sed -n 's/.*End=\([0-9.]*\)MiB.*/\1/p')
    free_total=$(echo "$selected_space" | sed -n 's/.*Size=\([0-9.]*\)MiB.*/\1/p')

    if [[ $free_total -le 0 ]]; then
        echo "Erreur : L'espace sélectionné est insuffisant pour créer des partitions."
        exit 1
    fi

    echo "Espace total disponible dans la plage sélectionnée : ${free_total} MiB"

    # Lecture des tailles de partitions
    read -p "Taille de la partition boot (en MiB, par défaut 512) : " boot_size
    boot_size=${boot_size:-512}

    read -p "Taille de la partition swap (en MiB, par défaut 4096) : " swap_size
    swap_size=${swap_size:-4096}

    # Calcul de la partition root
    root_size=$((free_total - boot_size - swap_size))

    if [[ $root_size -le 0 ]]; then
        echo "Erreur : L'espace non alloué est insuffisant pour créer les partitions."
        exit 1
    fi

    # Affichage des tailles
    echo "Taille de la partition boot : ${boot_size} MiB"
    echo "Taille de la partition swap : ${swap_size} MiB"
    echo "Taille de la partition root (calculée) : ${root_size} MiB"

    # Confirmation avant de créer les partitions
    read -p "Souhaitez-vous continuer avec ces paramètres ? (oui/non) : " continue
    if [[ "$continue" != "oui" ]]; then
        echo "Abandon."
        exit 1
    fi

    # Compte le nombre de partitions existantes
    part_count=$(lsblk -n -o NAME "/dev/$disk" | grep -E "$(basename "/dev/$disk")[0-9]+" | wc -l)

    # Le numéro de la nouvelle partition est part_count + 1
    # BOOT_PART_NUM=$((part_count + 1))
    # SWAP_PART_NUM=$((part_count + 2))

    # # Création de la partition boot
    # echo "Création de la partition boot..."
    # parted --script "/dev/$disk" mkpart primary fat32 "${free_start}MiB" "$((free_start + boot_size))MiB"

    # # Activation de l'attribut ESP sur la nouvelle partition boot
    # echo "Activation de l'attribut ESP sur la partition boot (partition numéro $BOOT_PART_NUM)..."
    # parted --script "/dev/$disk" set "$BOOT_PART_NUM" esp on

    # echo "Création de la partition swap..."
    # parted --script "/dev/$disk" mkpart primary linux-swap "$((free_start + boot_size))MiB" "$((free_start + boot_size + swap_size))MiB"
    # parted --script "/dev/$disk" set "$SWAP_PART_NUM" swap on

    # echo "Création de la partition root..."
    # parted --script "/dev/$disk" mkpart primary ext4 "$((free_start + boot_size + swap_size))MiB" "$free_end"MiB

    # # Formate les partitions
    # BOOT_PART="/dev/$disk $(lsblk -n -o NAME "/dev/$disk" | grep -E '^.*1$')"
    # SWAP_PART="/dev/$disk $(lsblk -n -o NAME "/dev/$disk" | grep -E '^.*2$')"
    # ROOT_PART="/dev/$disk $(lsblk -n -o NAME "/dev/$disk" | grep -E '^.*3$')"

    # echo "Formatage de la partition boot en vfat..."
    # mkfs.vfat "$BOOT_PART"

    # echo "Activation de la partition swap..."
    # mkswap "$SWAP_PART"
    # swapon "$SWAP_PART"

    # echo "Formatage de la partition root en ext4..."
    # mkfs.ext4 "$ROOT_PART"

    # # Résumé
    # echo "Partitionnement terminé avec succès !"
    # lsblk "/dev/$disk"

}