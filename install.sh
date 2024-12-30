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

        echo
        echo "$(show_disk_partitions "Le disque n'est pas vierge" "$disk")"
        echo

    fi

    echo "Que souhaitez-vous faire : " && echo

    echo "1) Formatage du disque          ==> Suppression des données sur /dev/$disk"
    echo "2) Installation de Arch Linux   ==> Espace total sur le disque /dev/$disk"
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
            preparation_disk "$disk"
            mount_partitions "$disk"
            show_disk_partitions "Montage des partitions terminée" "$disk"
            install_base "$disk"
            install_base_chroot "$disk"
            install_base_secu
            activate_service

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