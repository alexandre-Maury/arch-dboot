#!/bin/bash


test_disk() {

    DISK="$1"
    DISK_PATH="/dev/$DISK"

    if [[ ! -b "$DISK_PATH" ]]; then
        echo "Le disque $DISK_PATH n'existe pas."
        exit 1
    fi

    # Vérifie l'espace non alloué
    FREE_SPACE=$(parted "$DISK_PATH" unit MiB print free | awk '/Free Space/ {print $2, $3}' | tail -n1)
    FREE_START=$(echo "$FREE_SPACE" | awk '{print $1}' | tr -d 'MiB' | awk '{printf "%d", $1}')
    FREE_END=$(echo "$FREE_SPACE" | awk '{print $2}' | tr -d 'MiB' | awk '{printf "%d", $1}')

    if [[ -z "$FREE_START" || -z "$FREE_END" || "$FREE_START" == "$FREE_END" ]]; then
        echo "Aucun espace non alloué disponible sur $DISK_PATH."
        exit 1
    fi

    # Calcul de l'espace disponible total
    FREE_TOTAL=$((FREE_END - FREE_START))
    echo "Espace total disponible : ${FREE_TOTAL} MiB"

    # Lecture des tailles de partitions
    read -p "Taille de la partition boot (en MiB, par défaut 512) : " BOOT_SIZE
    BOOT_SIZE=${BOOT_SIZE:-512}  # Valeur par défaut : 512 MiB

    read -p "Taille de la partition swap (en MiB, par défaut 4096) : " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-4096}  # Valeur par défaut : 4096 MiB

    # Le reste pour la partition root
    ROOT_SIZE=$((FREE_TOTAL - BOOT_SIZE - SWAP_SIZE))

    if [[ $ROOT_SIZE -le 0 ]]; then
        echo "L'espace non alloué est insuffisant pour créer les partitions."
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
    echo "Partition boot : $BOOT_PART (${BOOT_SIZE} MiB, vfat)"
    echo "Partition swap : $SWAP_PART (${SWAP_SIZE} MiB, swap activé)"
    echo "Partition root : $ROOT_PART (${ROOT_SIZE} MiB, btrfs)"

}