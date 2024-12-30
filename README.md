# arch-dboot

Un script d'installation d'Arch Linux en mode UEFI, conçu pour automatiser les étapes critiques du processus d'installation et faciliter le double boot avec Windows.
Il prend en charge le partitionnement GPT, l'installation des paquets de base, la configuration du système et le déploiement du chargeur de démarrage systemd-boot.
Le script est optimisé pour un système de fichiers btrfs, tout en maintenant la compatibilité avec les partitions Windows existantes.

⚠️ Ce script reste en cours d'amélioration. De nouvelles fonctionnalités et optimisations sont régulièrement ajoutées pour répondre aux besoins.

## Processus automatisé

Table de partition GPT : Assure la compatibilité avec UEFI et les environnements double boot.
Partitionnement dynamique : Préserve les partitions Windows existantes et crée les partitions nécessaires pour Arch Linux, configurables via un fichier config.sh.
Système de fichiers btrfs : Exploite les fonctionnalités modernes telles que la compression, les sous-volumes et les snapshots.

## Partitions typiques pour le double boot :

    EFI : 512MiB en fat32, partageable avec Windows pour le chargeur de démarrage.
    SWAP : 8GiB en linux-swap (ou une taille définie par l'utilisateur).
    ROOT : Utilise le reste de l'espace disque avec btrfs.

### Exemple de configuration des partitions dans config.sh :

    PARTITIONS_CREATE=(
        "efi:${DEFAULT_BOOT_SIZE}:${DEFAULT_BOOT_TYPE}"  
        "swap:${DEFAULT_SWAP_SIZE}:${DEFAULT_SWAP_TYPE}"
        "root:${DEFAULT_FS_SIZE}:${DEFAULT_FS_TYPE}"
    )

### Montage des partitions :

    EFI (arch) : Montée dans /mnt/boot.
    EFI (windows) : Montée dans /mnt/boot/EFI.
    ROOT : Montée dans /mnt avec des sous-volumes btrfs personnalisés.

### Installation et configuration système :

Installation des paquets essentiels d'Arch Linux (base, linux, linux-firmware, etc.).
Configuration de locales, fuseau horaire, clavier, réseau et nom d'hôte via config.sh.

### Chargeur de démarrage :

Systemd-boot : Configuré pour détecter et gérer les systèmes existants (Windows inclus).
Inclut des options prédéfinies pour faciliter le démarrage de Windows depuis le menu systemd-boot.

## Instructions d'utilisation

Clonez le dépôt contenant le script :

    git clone https://github.com/alexandre-Maury/arch-efi.git
    cd arch-efi

Modifiez le fichier config.sh selon vos besoins :

    nano config.sh

Lancez le script d'installation :

    chmod +x install.sh && ./install.sh

## Points forts

Optimisé pour le double boot : Maintient la compatibilité avec Windows tout en utilisant les fonctionnalités modernes de Linux.
Support btrfs : Compression, snapshots et sous-volumes pour un système flexible.
Personnalisable : Les paramètres sont ajustables via un fichier de configuration simple.
Chargeur de démarrage intégré : Systemd-boot simplifie la gestion des systèmes UEFI modernes.

⚠️ Améliorations en cours : Le script évolue pour intégrer des fonctionnalités supplémentaires et renforcer sa stabilité.
Auteurs et contribution


## Auteur : 

    Alexandre MAURY

## Contributeur principal : 

    Alexandre MAURY