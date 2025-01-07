# arch-dboot [EN COURS]

Un script d'installation d'Arch Linux en mode UEFI, conçu pour automatiser les étapes critiques du processus d'installation et faciliter le double boot avec Windows.
Il prend en charge le partitionnement GPT, l'installation des paquets de base, la configuration du système et le déploiement du chargeur de démarrage systemd-boot.
Le script est optimisé pour un système de fichiers btrfs, tout en maintenant la compatibilité avec les partitions Windows existantes.

⚠️ Ce script reste en cours d'amélioration. De nouvelles fonctionnalités et optimisations sont régulièrement ajoutées pour répondre aux besoins.

## Processus automatisé

Assure la compatibilité avec UEFI et les environnements dual boot. Préserve les partitions Windows existantes et crée les partitions nécessaires pour Arch Linux à l'aide de deux modes de partitionnement.
Système de fichiers conseillé pour la partition racine (root):

    btrfs : 
    
    Exploite les fonctionnalités modernes telles que la compression, les sous-volumes et les snapshots.

    Taille de la partition conseillé : 100%
    Liste des sous-volumes par défaut : "@" "@root" "@home" "@srv" "@log" "@cache" "@tmp" "@snapshots"
    Options de montage BTRFS par défaut : defaults,noatime,compress=zstd,commit=120

Ses Options (liste des sous-volumes et options de montage) sont modifiable dans le fichier config.sh.

    # Liste des sous-volumes BTRFS à créer
    BTRFS_SUBVOLUMES=("@" "@root" "@home" "@srv" "@log" "@cache" "@tmp" "@snapshots")

    # Options de montage BTRFS par défaut
    BTRFS_MOUNT_OPTIONS="defaults,noatime,compress=zstd,commit=120"
    
1- <u> Mode Standard : (valeurs par défaut) </u>

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

2- <u> Mode Avancé : (configuration manuelle) </u>

Vous pouvez configurer les partitions selon vos besoins, dans la limite des contraintes du programme.
Le double boot est possible dans ce mode.


## Partitions typiques pour le double boot :

Liste des partitions :

    Ex. disque principal : sda
    
    sda1 <-- EFI Partition
    sda2 <-- MSR
    sda3 <-- Windows
    sda4 <-- Empty Partition for Linux

<u> - Partition 'EFI' : </u>

Lors de la sélection des partitions durant l'éxécution de se script, LORS D'UN DUAL BOOT, il est important de ne pas créer de nouveau une partition boot (efi). 
Celle de Windows sera utilisé. Cette partition doit donc être créée avant l'installation de Windows d'une taille minimun de 512 MiB.


<u> - Partition 'SWAP' : Selon vos préférences</u>


<u> - Partition 'RACINE' : </u>

Réduisez la taille d'une partition existante pour libérer de l'espace.
La nouvelle partition 'root' sera utilisée pour le système Arch Linux.
Vous pouvez utiliser des outils de partitionnement pour redimensionner les partitions.


    Utilisez l'outil de votre choix, comme le live CD d'Arch Linux avec 'cfdisk' ou 'diskpart' de Windows.


Exemple : (diskpart)

    Illustration a venir

    <!-- ![image description](https://github.com/alexandre-Maury/arch-dboot/blob/main/assets/config.png) -->

    

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

    git clone https://github.com/alexandre-Maury/arch-dboot.git
    cd arch-dboot

Modifiez le fichier config.sh selon vos besoins :

    nano config.sh

Lancez le script d'installation :

    chmod +x install.sh && ./install.sh

## Points forts

Optimisé pour le double boot : Maintient la compatibilité avec Windows tout en utilisant les fonctionnalités modernes de Linux.
Support btrfs : Compression, snapshots et sous-volumes pour un système flexible.
Personnalisable : Les paramètres sont ajustables via un fichier de configuration simple.
Chargeur de démarrage intégré : Systemd-boot simplifie la gestion des systèmes UEFI modernes.

⚠️ Améliorations en cours : 

    Le script évolue pour intégrer des fonctionnalités supplémentaires et renforcer sa stabilité.

## Trouble shooting

### Disparition de l'entrée de démarrage pour Windows dans le chargeur GRUB

Même si os-prober est installé et que la ligne suivante est correctement configurée dans /etc/default/grub :

    GRUB_DISABLE_OS_PROBER=false

il peut arriver que Windows n'apparaisse pas parmi les options de démarrage.

Pas de panique !

Au prochain redémarrage du système, exécutez la commande suivante pour régénérer le fichier de configuration de GRUB :

    sudo grub-mkconfig -o /boot/grub/grub.cfg

Cela devrait détecter Windows et ajouter son entrée au chargeur de démarrage GRUB.


## Auteur : 

    Alexandre MAURY

## Contributeur principal : 

    Alexandre MAURY