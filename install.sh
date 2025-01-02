#!/bin/bash

# script install.sh
# Ce script constitue le point d'entrée pour l'installation, 
# en regroupant les fichiers de configuration et fonctions nécessaires.

set -e  
# Active le mode "exit on error". Si une commande retourne une erreur, le script s'arrête immédiatement.
# Cela garantit que les étapes critiques ne sont pas ignorées.

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Détermine le chemin absolu du répertoire contenant ce script.
# Cette approche rend le script portable et lui permet de toujours localiser les fichiers nécessaires,
# quel que soit le répertoire à partir duquel il est exécuté.

source $SCRIPT_DIR/config/config.sh
# Charge le fichier de configuration situé dans le sous-dossier config.

source $SCRIPT_DIR/functions/functions.sh  
# Charge un fichier contenant des fonctions utilitaires génériques.

source $SCRIPT_DIR/functions/functions_disk.sh  
# Charge un fichier contenant des fonctions spécifiques à la gestion des disques.

source $SCRIPT_DIR/functions/functions_install.sh  
# Charge un fichier contenant des fonctions dédiées à l'installation du système.

##############################################################################
## Vérifier les privilèges root
##############################################################################
if [ "$EUID" -ne 0 ]; then
  log_prompt "ERROR" && echo "Veuillez exécuter ce script en tant qu'utilisateur root."
  exit 1
fi

##############################################################################
## Valide la connexion internet                                                          
##############################################################################
echo
log_prompt "INFO" && echo "Vérification de la connexion Internet"
$(ping -c 3 archlinux.org &>/dev/null) || (log_prompt "ERROR" && echo "Pas de connexion Internet" && echo)
sleep 2

##############################################################################
## Récupération des disques disponibles                                                      
##############################################################################
list="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 

if [[ -z "${list}" ]]; then
    log_prompt "ERROR" && echo "Aucun disque disponible pour l'installation."
    exit 1  # Arrête le script ou effectue une autre action en cas d'erreur
else
    clear
    echo
    log_prompt "INFO" && echo "Choisissez un disque pour l'installation (ex : 1) " && echo
    echo "${list}" && echo
fi

# Boucle pour que l'utilisateur puisse choisir un disque ou en entrer un manuellement
option=""
while [[ -z "$(echo "${list}" | grep "  ${option})")" ]]; do
    
    log_prompt "INFO" && read -p "Votre Choix : " option 
    
    # Vérification si l'utilisateur a entré un numéro (choix dans la liste)
    if [[ -n "$(echo "${list}" | grep "  ${option})")" ]]; then
        # Si l'utilisateur a choisi un numéro valide, récupérer le nom du disque correspondant
        disk="$(echo "${list}" | grep "  ${option})" | awk '{print $2}')"
        break
    else
        # Si l'utilisateur a entré quelque chose qui n'est pas dans la liste, considérer que c'est un nom de disque
        disk="${option}"
        break
    fi
done

clear

##############################################################################
## MENU                                                     
##############################################################################
while true; do

    partitions=$(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}\([0-9]*\)$/${disk}\1/p")

    # Vérifie si des partitions existent
    if [ -z "$partitions" ]; then

        echo
        echo "Status : Le disque est vierge"
        echo "Device : /dev/$disk"
        echo "Taille : $(lsblk -n -o SIZE "/dev/$disk" | head -1)"
        echo "Type   : $(lsblk -n -o TRAN "/dev/$disk")"
        echo

    else
        clear
        echo
        echo "$(show_disk_partitions "Le disque n'est pas vierge" "$disk")"
        echo

    fi

    echo "Que souhaitez-vous faire : " && echo

    echo "1) Nettoyage du disque          ==> Suppression des données sur /dev/$disk"
    echo "2) Installation de Arch Linux   ==> Double boot"
    echo
    echo "0) Annuler"
    echo

    log_prompt "INFO" && read -p "Votre Choix (0-2) " choice && echo

    case $choice in
        1)
            clear
            erase_disk "$disk"
            break
            ;;
        2)
            clear
            echo
        
            echo "Pour procéder à une installation en double boot, vous devez préparer les partitions nécessaires."
            echo "Voici les partitions à spécifier :"
            echo
            echo "1. Partition '/EFI' :"
            echo "   - Cette partition est créée au préalable par Windows."
            echo "   - Assurez-vous de connaître le nom de la partition (ex. /dev/sda1) => Elle vous sera demandé lors de l'installation"
            echo
            echo "2. Partition '/root' :"
            echo "   - La partition racine doit être créée par vos soins, généralement en réduisant la partition système existante."
            echo "   - Vous pouvez utiliser un outil de partitionnement pour redimensionner la partition actuelle afin de libérer de l'espace pour la partition 'root'."
            echo
            echo "⚠️ Remarque importante : Veuillez être prudent lors de la réduction des partitions existantes."
            echo "     La réduction incorrecte d'une partition système pourrait entraîner une perte de données."
            echo "     Assurez-vous d'avoir effectué une sauvegarde complète avant de procéder."
            echo
            show_disk_partitions "Préparation de l'installation" "$disk"

            log_prompt "INFO" && read -p "1- Saisir le nom de la partition de démarrage /EFI de votre système (ex. sda1) : " partition_boot_windows
            preparation_disk "$disk"
            mount_partitions "$disk"
            show_disk_partitions "Montage des partitions terminée" "$disk"
            # install_base "$disk"
            # install_base_chroot "$disk"
            # install_base_secu
            # activate_service

            log_prompt "INFO" && echo "Installation terminée ==> redémarrer votre systeme"
            break
            ;;

        0)
            log_prompt "WARNING" && echo "Opération annulée"
            exit 0
            ;;
        *)
            echo "Choix invalide"
            ;;
    esac
done