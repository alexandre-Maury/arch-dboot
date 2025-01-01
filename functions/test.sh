#!/bin/bash


test_disk() {

    DISK="$1"
    DISK_PATH="/dev/$DISK"

    if [[ ! -b "$DISK_PATH" ]]; then
        echo "Le disque $DISK_PATH n'existe pas."
        exit 1
    fi

    AVAILABLE_SPACES=$(parted "$DISK_PATH" unit MiB print free | awk '/Free Space/ {print NR": Start="$1", End="$2", Size="$3}')

    if [[ -z "$AVAILABLE_SPACES" ]]; then
        echo "Aucun espace libre détecté sur $DISK_PATH."
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

    # Crée les partitions
    echo "Création de la partition boot..."
    parted --script "$DISK_PATH" mkpart primary fat32 "${FREE_START}MiB" "$((FREE_START + BOOT_SIZE))MiB"
    
    # # Identification du numéro de la partition créée
    BOOT_PART_NUM=$(parted "$DISK_PATH" unit MiB print | awk -v start="${FREE_START}" '/fat32/ && $2 ~ start {print $1}')

    echo "partition nouvelle : $BOOT_PART_NUM"


    # # Activation de l'attribut ESP sur la partition boot
    # echo "Activation de l'attribut ESP sur la partition boot (partition numéro $BOOT_PART_NUM)..."
    # parted --script "$DISK_PATH" set "$BOOT_PART_NUM" esp on

    # echo "Création de la partition swap..."
    # parted --script "$DISK_PATH" mkpart primary linux-swap "$((FREE_START + BOOT_SIZE))MiB" "$((FREE_START + BOOT_SIZE + SWAP_SIZE))MiB"
    # # parted --script "$DISK_PATH" set "$BOOT_PART_NUM" swap on

    # echo "Création de la partition root..."
    # parted --script "$DISK_PATH" mkpart primary ext4 "$((FREE_START + BOOT_SIZE + SWAP_SIZE))MiB" "$FREE_END"MiB

    # # Formate les partitions
    # BOOT_PART="${DISK_PATH}$(lsblk -n -o NAME "$DISK_PATH" | grep -E '^.*1$')"
    # SWAP_PART="${DISK_PATH}$(lsblk -n -o NAME "$DISK_PATH" | grep -E '^.*2$')"
    # ROOT_PART="${DISK_PATH}$(lsblk -n -o NAME "$DISK_PATH" | grep -E '^.*3$')"

    # echo "Formatage de la partition boot en vfat..."
    # mkfs.vfat "$BOOT_PART"

    # echo "Activation de la partition swap..."
    # mkswap "$SWAP_PART"
    # swapon "$SWAP_PART"

    # echo "Formatage de la partition root en ext4..."
    # mkfs.ext4 "$ROOT_PART"

    # # Résumé
    # echo "Partitionnement terminé avec succès !"
    # lsblk "$DISK_PATH"

}