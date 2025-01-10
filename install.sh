#!/bin/bash

# script install.sh
# Ce script constitue le point d'entrée pour l'installation, 
# en regroupant les fichiers de configuration et fonctions nécessaires.

set -e  

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

source $SCRIPT_DIR/env/system.sh 
source $SCRIPT_DIR/config/config.sh
source $SCRIPT_DIR/functions/functions.sh  
source $SCRIPT_DIR/functions/functions_disk.sh  
source $SCRIPT_DIR/functions/functions_install.sh  


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
# echo
# log_prompt "INFO" && echo "Vérification de la connexion Internet"
# $(ping -c 3 archlinux.org &>/dev/null) || (log_prompt "ERROR" && echo "Pas de connexion Internet" && echo)
# sleep 2

##############################################################################
## Récupération des disques disponibles                                                      
##############################################################################
if [[ -z "${LIST_DISK}" ]]; then
    log_prompt "ERROR" && echo "Aucun disque disponible pour l'installation."
    exit 1  # Arrête le script ou effectue une autre action en cas d'erreur
else
    clear
    echo
    log_prompt "INFO" && echo "Choisissez un disque pour l'installation (ex : 1) " && echo
    echo "${LIST_DISK}" && echo
fi

# Boucle pour que l'utilisateur puisse choisir un disque ou en entrer un manuellement
option=""
while [[ -z "$(echo "${LIST_DISK}" | grep "  ${option})")" ]]; do
    
    log_prompt "PROMPT" && read -p "Votre Choix : " option 
    
    # Vérification si l'utilisateur a entré un numéro (choix dans la liste)
    if [[ -n "$(echo "${LIST_DISK}" | grep "  ${option})")" ]]; then
        # Si l'utilisateur a choisi un numéro valide, récupérer le nom du disque correspondant
        disk="$(echo "${LIST_DISK}" | grep "  ${option})" | awk '{print $2}')"
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
    echo
    echo "----------------------------------------"
    echo
    echo " - INTERFACE : $INTERFACE"
    echo " - ADRESSE MAC : $MAC_ADDRESS"
    echo " - Total de RAM : $RAM"
    echo " - CPU : $CPU_VENDOR"
    echo " - Nombres de coeur : $CPU_COEUR"
    echo " - GPU : $GPU_VENDOR"
    echo
    echo "----------------------------------------"

    # partitions=$(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}\([0-9]*\)$/${disk}\1/p")
    partitions=$(lsblk -n -o NAME "/dev/$disk" | grep -v "^$disk$" | sed -n "s/^[[:graph:]]*${disk}${disk_prefix}\([0-9]*\)$/${disk}${disk_prefix}\1/p")

    echo "mes partitions : $partitions"


    # Vérifie si des partitions existent
    if [ -z "$partitions" ]; then
        echo
        echo "Status : Le disque est vierge"
        echo "Device : /dev/$disk"
        echo "Taille : $(lsblk -n -o SIZE "/dev/$disk" | head -1)"
        echo "Type   : $(lsblk -n -o TRAN "/dev/$disk")"
        echo

        dboot=False

    else
        echo
        echo "$(show_disk_partitions "Partitions présente sur le disque" "$disk")"
        echo

        dboot=True
    fi

    echo "Que souhaitez-vous faire : " && echo

    echo "1) Nettoyage du disque (shred)   "
    echo "2) Installation de Arch Linux    "
    echo "3) Réinstallation de Arch Linux  "
    echo
    echo "0) Annuler"
    echo

    log_prompt "PROMPT" && read -p "Votre Choix (0-2) " choice && echo

    case $choice in
        1)
            clear
            erase_disk "$disk"
            log_prompt "INFO" && echo "Suppression des données terminé"
            ;;
        2)
            clear
            echo
            manage_partitions "$disk" "$dboot"
            mount_partitions "$disk"
            show_disk_partitions "Montage des partitions terminée" "$disk" 
            # install_base 
            # config_system
            # install_packages
            # install_mkinitcpio
            # install_bootloader "$disk"
            # config_passwdqc
            # config_root
            # config_user
            # config_ssh
            # activate_service

            clear
            echo
            log_prompt "INFO" && echo "Installation terminée ==> redémarrer votre systeme"
            break
            ;;

        3)
            clear
            echo "PAS ENCORE DISPONIBLE"
            ;;

        0)
            log_prompt "WARNING" && echo "Opération annulée"
            echo
            break
            ;;
        *)
            echo "Choix invalide"
            ;;
    esac
done