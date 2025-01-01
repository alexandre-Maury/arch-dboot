#!/bin/bash


test_disk() {

    disk="$1"
    DISK_PATH="/dev/$disk"

    if [[ ! -b "/dev/$disk" ]]; then
        echo "Le disque /dev/$disk n'existe pas."
        exit 1
    fi

    AVAILABLE_SPACES=$(parted "/dev/$disk" unit MiB print free | awk '/Free Space/ {print NR": Start="$1", End="$2", Size="$3}')

    if [[ -z "$AVAILABLE_SPACES" ]]; then
        echo "Aucun espace libre détecté sur /dev/$disk."
        exit 1
    fi

    echo "Liste des espaces libres disponibles :"
    echo "$AVAILABLE_SPACES" | awk -F'[:,]' '{print $1 " - Espace disponible : " $NF}'

    # Propose à l'utilisateur de choisir un espace libre
    read -p "Veuillez entrer le numéro de la plage d'espace libre à utiliser : " SPACE_CHOICE

    SELECTED_SPACE=$(echo "$AVAILABLE_SPACES" | grep "^${SPACE_CHOICE}:")
    if [[ -z "$SELECTED_SPACE" ]]; then
        echo "Choix invalide. Veuillez réessayer."
        exit 1
    fi

    FREE_START=$(echo "$SELECTED_SPACE" | sed -n 's/.*Start=\([0-9.]*\)MiB.*/\1/p')
    FREE_END=$(echo "$SELECTED_SPACE" | sed -n 's/.*End=\([0-9.]*\)MiB.*/\1/p')
    FREE_TOTAL=$(echo "$SELECTED_SPACE" | sed -n 's/.*Size=\([0-9.]*\)MiB.*/\1/p')

    if [[ $FREE_TOTAL -le 0 ]]; then
        echo "Erreur : L'espace sélectionné est insuffisant pour créer des partitions."
        exit 1
    fi

    echo "Espace total disponible dans la plage sélectionnée : ${FREE_TOTAL} MiB"

    # Lecture des tailles de partitions
    read -p "Taille de la partition boot (en MiB, par défaut 512) : " BOOT_SIZE
    BOOT_SIZE=${BOOT_SIZE:-512}

    read -p "Taille de la partition swap (en MiB, par défaut 4096) : " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-4096}

    # Calcul de la partition root
    ROOT_SIZE=$((FREE_TOTAL - BOOT_SIZE - SWAP_SIZE))

    if [[ $ROOT_SIZE -le 0 ]]; then
        echo "Erreur : L'espace non alloué est insuffisant pour créer les partitions."
        exit 1
    fi

    # Affichage des tailles
    echo "Taille de la partition boot : ${BOOT_SIZE} MiB"
    echo "Taille de la partition swap : ${SWAP_SIZE} MiB"
    echo "Taille de la partition root (calculée) : ${ROOT_SIZE} MiB"

    # Confirmation avant de créer les partitions
    read -p "Souhaitez-vous continuer avec ces paramètres ? (oui/non) : " CONTINUE
    if [[ "$CONTINUE" != "oui" ]]; then
        echo "Abandon."
        exit 1
    fi

    # Compte le nombre de partitions existantes
    PART_COUNT=$(lsblk -n -o NAME "/dev/$disk" | grep -E "$(basename "/dev/$disk")[0-9]+" | wc -l)

    echo "nb de partitions existante : $PART_COUNT"

    # Le numéro de la nouvelle partition est PART_COUNT + 1
    # BOOT_PART_NUM=$((PART_COUNT + 1))
    # SWAP_PART_NUM=$((PART_COUNT + 2))

    # # Création de la partition boot
    # echo "Création de la partition boot..."
    # parted --script "/dev/$disk" mkpart primary fat32 "${FREE_START}MiB" "$((FREE_START + BOOT_SIZE))MiB"

    # # Activation de l'attribut ESP sur la nouvelle partition boot
    # echo "Activation de l'attribut ESP sur la partition boot (partition numéro $BOOT_PART_NUM)..."
    # parted --script "/dev/$disk" set "$BOOT_PART_NUM" esp on

    # echo "Création de la partition swap..."
    # parted --script "/dev/$disk" mkpart primary linux-swap "$((FREE_START + BOOT_SIZE))MiB" "$((FREE_START + BOOT_SIZE + SWAP_SIZE))MiB"
    # parted --script "/dev/$disk" set "$SWAP_PART_NUM" swap on

    # echo "Création de la partition root..."
    # parted --script "/dev/$disk" mkpart primary ext4 "$((FREE_START + BOOT_SIZE + SWAP_SIZE))MiB" "$FREE_END"MiB

    # # Formate les partitions
    # BOOT_PART="${DISK_PATH}$(lsblk -n -o NAME "/dev/$disk" | grep -E '^.*1$')"
    # SWAP_PART="${DISK_PATH}$(lsblk -n -o NAME "/dev/$disk" | grep -E '^.*2$')"
    # ROOT_PART="${DISK_PATH}$(lsblk -n -o NAME "/dev/$disk" | grep -E '^.*3$')"

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