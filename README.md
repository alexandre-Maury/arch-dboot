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

## Mode de partitionnement

Pour créer vos partitions, vous avez le choix entre deux modes de partitionnement.

### Mode Standard : (valeurs par défaut) 

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

### Mode Avancé : (configuration manuelle)

Vous pouvez configurer les partitions selon vos besoins, dans la limite des contraintes du programme.
Le double boot est possible dans ce mode.


## Partitions typiques :


Ex. disque principal : sda

### Pour un Dual Boot :

    sda1 <-- EFI Partition
    sda2 <-- MSR
    sda3 <-- Windows
    sda4 <-- Linux Swap (facultatif)
    sda5 <-- Linux Racine
    sda6 <-- Linux Home (facultatif)

### Pour une installation simple boot

    sda1 <-- EFI Partition
    sda2 <-- Linux Swap (facultatif)
    sda3 <-- Linux Racine
    sda4 <-- Linux Home (facultatif)

- Partition 'EFI' : Taille minimun de 512 MiB.
LORS D'UN DUAL BOOT, au cours de la sélection des partitions durant l'éxécution de se script, il est important de ne pas créer de nouveau une partition boot (efi). 
Celle de Windows sera utilisé. Cette partition doit donc être créée avant l'installation de Windows.

- Partition 'MSR' : Taille recommandé 16 MiB
Zone réservée pour Windows, afin d'y stocker des données système spécifiques.

- Partition 'WINDOWS' : (Taille facultatif - Selon vos préférences)
La partition Windows sera utilisée pour l'installation du système de Windows. 

- Partition 'SWAP' : (Taille facultatif - Selon vos préférences)
Espace de stockage utilisé comme mémoire virtuelle lorsque la mémoire vive (RAM) est insuffisante pour répondre aux besoins du système.

- Partition 'RACINE' : 
La partition Racine 'root' sera utilisée pour l'installation du système de Linux.

- Partition 'HOME' : (facultatif) 
La partition 'home' sera utilisée pour stocker les données personnelles des utilisateurs. 


Utilisez l'outil de votre choix, comme le live CD d'Arch Linux avec 'cfdisk' ou 'diskpart' de Windows pour la création des partitions.


## Exemple :

### Création des partitions avec diskpart :

Lorsque vous arrivez à l'écran de sélection du disque d'installation de Windows, appuyez sur les touches Maj + F10 pour ouvrir l'invite de commandes.

Ensuite, procédez comme suit : Saisissez les commandes suivantes pour accéder à l'outil Diskpart et sélectionner le disque à partitionner :

    diskpart  
    list disk  
    select disk X  (remplacez **X** par le numéro du disque, par exemple **0**)
    clean
    convert gpt

![image description](https://github.com/alexandre-Maury/arch-dboot/blob/main/assets/1.png)

Créez les partitions nécessaires en exécutant ces commandes :

    create partition efi size=512  
    create partition msr size=16  
    create partition primary  

![image description](https://github.com/alexandre-Maury/arch-dboot/blob/main/assets/2.png)

Une fois terminé, quittez l'invite de commandes en saisissant :

    exit  
    exit  

Cliquez ensuite sur "Actualiser" dans l'interface de l'installation de Windows pour voir apparaître les partitions créées.

![image description](https://github.com/alexandre-Maury/arch-dboot/blob/main/assets/3.png)

    
### Réduction d’un disque via le Gestionnaire de disque :
    

⚠️ Remarque importante :

Soyez extrêmement prudent lors du redimensionnement des partitions existantes."
Une mauvaise manipulation peut entraîner une perte de données."
Assurez-vous d'avoir effectué une sauvegarde complète de vos données avant de continuer."

Ouvrir le Gestionnaire de disque :

    Appuyez sur Win + R pour ouvrir la boîte de dialogue "Exécuter".
    Tapez diskmgmt.msc et appuyez sur Entrée.

Identifier le disque à réduire :

    Repérez le disque ou la partition principale (souvent le disque C: contenant Windows).
    Vérifiez que le disque a suffisamment d’espace libre pour être réduit.

Réduire le disque :

    Faites un clic droit sur la partition que vous souhaitez réduire, puis cliquez sur Réduire le volume.
    Windows calculera automatiquement l’espace disponible pour la réduction.
    Saisissez la quantité d’espace à libérer (en Mo) dans le champ correspondant. Par exemple, pour libérer 150 Go, entrez 150000 (1 Go = 1024 Mo).
    Cliquez sur Réduire.

Créer un espace non alloué :

    Une fois la réduction effectuée, vous verrez une zone marquée Espace non alloué dans le Gestionnaire de disque. Cet espace sera utilisé pour installer Linux.

## Installation et configuration système :

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

    ##############################################################################
    ## Toute modification incorrecte peut entraîner des perturbations lors de l'installation                                                             
    ##############################################################################

    ZONE="Europe"
    PAYS="France"
    CITY="Paris"
    LANG="fr_FR.UTF-8"
    LOCALE="fr_FR"
    KEYMAP="fr"
    HOSTNAME="archlinux-alexandre"
    SSH_PORT=2222  # Remplacez 2222 par le port que vous souhaitez utiliser

    MOUNT_POINT="/mnt" # Point de montage   

    DEFAULT_BOOT_TYPE="fat32"
    DEFAULT_SWAP_TYPE="linux-swap"
    DEFAULT_ROOT_TYPE="ext4"
    DEFAULT_HOME_TYPE="ext4"

    DEFAULT_BOOT_SIZE="512MiB"
    DEFAULT_SWAP_SIZE="8GiB"
    DEFAULT_ROOT_SIZE="55GiB"
    DEFAULT_HOME_SIZE="100%"

    PARTITIONS_CREATE=(
        "boot:${DEFAULT_BOOT_SIZE}:${DEFAULT_BOOT_TYPE}"
        "swap:${DEFAULT_SWAP_SIZE}:${DEFAULT_SWAP_TYPE}"
        "root:${DEFAULT_ROOT_SIZE}:${DEFAULT_ROOT_TYPE}"
        "home:${DEFAULT_HOME_SIZE}:${DEFAULT_HOME_TYPE}"
    )

    PARTITIONS_TYPE=(
        "linux-swap"
        "ext4"
        "btrfs"
        "fat32"
    )

    BOOTLOADER="grub"  # systemd-boot ou grub

    # Liste des sous-volumes BTRFS à créer
    BTRFS_SUBVOLUMES=("@" "@root" "@home" "@srv" "@log" "@cache" "@tmp" "@snapshots")

    # Options de montage BTRFS par défaut
    BTRFS_MOUNT_OPTIONS="defaults,noatime,compress=zstd,commit=120"

⚠️ Améliorations en cours : 

    Le script évolue pour intégrer des fonctionnalités supplémentaires et renforcer sa stabilité.

## Dépannage (Troubleshooting)

Windows peut être un système assez capricieux lorsqu'il cohabite avec d'autres systèmes d'exploitation. Il n’est pas rare que des ajustements soient nécessaires pour assurer un fonctionnement fluide en dual boot.

### Disparition de l'entrée de démarrage pour Windows dans le chargeur GRUB

Même si os-prober est installé et que la ligne suivante est correctement configurée dans /etc/default/grub :

    GRUB_DISABLE_OS_PROBER=false

il peut arriver que Windows n'apparaisse pas parmi les options de démarrage de grub.

Pas de panique ! Au prochain redémarrage du système de arch, exécutez la commande suivante pour régénérer le fichier de configuration de GRUB :

    sudo grub-mkconfig -o /boot/grub/grub.cfg

Cela devrait détecter Windows et ajouter son entrée au chargeur de démarrage GRUB.

### Corriger Grub ou systemd-boot qui ne s'affiche pas pour un dual boot (démarrage direct sur windows)

Lors de la configuration d'un système en dual boot (Windows et Linux), il peut arriver que Windows prenne le dessus sur le gestionnaire de démarrage Linux (Grub ou systemd-boot). Ce problème survient fréquemment après une mise à jour de Windows ou une configuration incorrecte dans le BIOS/UEFI.

1- Démarrez sur une session Windows.

2- Lancez une invite de commandes en tant qu'administrateur.

3- Réglez le gestionnaire de démarrage pour pointer vers systemd-boot ou grub selon votre choix :

#### systemd-boot

    bcdedit /set '{bootmgr}' path \EFI\Boot\bootx64.efi

#### grub

    bcdedit /set '{bootmgr}' path \EFI\GRUB\grubx64.efi

## Conseils supplémentaires

Vérifiez l’ordre de démarrage dans le BIOS/UEFI : Assurez-vous que la partition EFI contenant Grub ou systemd-boot est prioritaire dans les paramètres UEFI.

Désactivez le démarrage rapide de Windows : Cette option peut interférer avec le dual boot. Pour la désactiver :

1- Allez dans le Panneau de configuration > Options d’alimentation > Choisir l'action des boutons d'alimentation.

2- Décochez "Activer le démarrage rapide".

Ces solutions devraient permettre de corriger les problèmes courants liés au dual boot avec Windows et Linux. Si le problème persiste, vérifiez les logs ou partagez des informations supplémentaires pour obtenir une aide plus spécifique.

## Auteur : 

    Alexandre MAURY

## Contributeur principal : 

    Alexandre MAURY