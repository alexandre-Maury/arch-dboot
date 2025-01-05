# arch-dboot [EN COURS]

Un script d'installation d'Arch Linux en mode UEFI, conçu pour automatiser les étapes critiques du processus d'installation et faciliter le double boot avec Windows.
Il prend en charge le partitionnement GPT, l'installation des paquets de base, la configuration du système et le déploiement du chargeur de démarrage systemd-boot.
Le script est optimisé pour un système de fichiers btrfs, tout en maintenant la compatibilité avec les partitions Windows existantes.

⚠️ Ce script reste en cours d'amélioration. De nouvelles fonctionnalités et optimisations sont régulièrement ajoutées pour répondre aux besoins.

## Processus automatisé

Assure la compatibilité avec UEFI et les environnements dual boot. Préserve les partitions Windows existantes et crée les partitions nécessaires pour Arch Linux à l'aide de deux modes de partitionnement.
    
1- Mode Standard : (valeurs par défaut)

Les partitions seront créées en fonction des valeurs par défaut définies dans le fichier config.sh.
Le double boot n'est PAS activé dans ce mode.

ex.

    DEFAULT_BOOT_TYPE="fat32"
    DEFAULT_SWAP_TYPE="linux-swap"
    DEFAULT_FS_TYPE="btrfs"

    DEFAULT_BOOT_SIZE="512MiB"
    DEFAULT_SWAP_SIZE="8GiB"
    DEFAULT_FS_SIZE="100%"

    PARTITIONS_CREATE=(
        "boot:${DEFAULT_BOOT_SIZE}:${DEFAULT_BOOT_TYPE}"
        "swap:${DEFAULT_SWAP_SIZE}:${DEFAULT_SWAP_TYPE}"
        "root:${DEFAULT_FS_SIZE}:${DEFAULT_FS_TYPE}"
    )

2- Mode Avancé : (configuration manuelle)

Vous pouvez configurer les partitions selon vos besoins, dans la limite des contraintes du programme.
Le double boot est possible dans ce mode.

Système de fichiers btrfs : Exploite les fonctionnalités modernes telles que la compression, les sous-volumes et les snapshots.

## Partitions typiques pour le double boot :

    EFI : 512MiB en fat32, partageable avec Windows pour le chargeur de démarrage.
    SWAP : 8GiB en linux-swap (ou une taille définie par l'utilisateur).
    ROOT : Utilise le reste de l'espace disque avec btrfs.

Création de la partition '/EFI' :"

Lors de la sélection des partitions à venir lors de l'éxécution de se script, il est important de ne pas créer de nouveau une partition boot (efi). Lors d'un dual boot, celle de Windows sera utilisé.

    Cette partition doit être créée avant l'installation de Windows.
    Utilisez l'outil de votre choix, comme le live CD d'Arch Linux avec 'cfdisk' ou 'diskpart' de Windows.
    Assurez-vous de définir le type de partition sur 'EFI System Partition' (ESP).
    Taille minimale requise : 512 MiB.

Illustration a venir


Création de la partition '/root' :

Réduisez la taille d'une partition existante pour libérer de l'espace.
La nouvelle partition 'root' sera utilisée pour le système Arch Linux.
Vous pouvez utiliser des outils de partitionnement pour redimensionner les partitions.

⚠️ Remarque importante :

Soyez extrêmement prudent lors du redimensionnement des partitions existantes."
Une mauvaise manipulation peut entraîner une perte de données."
Assurez-vous d'avoir effectué une sauvegarde complète de vos données avant de continuer."

## Installation et configuration système :

Installation des paquets essentiels d'Arch Linux (base, linux, linux-firmware, etc.).
Configuration de locales, fuseau horaire, clavier, réseau et nom d'hôte via config.sh.

## Chargeur de démarrage :

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