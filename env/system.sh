#!/bin/bash

# script system.sh

##############################################################################
## Fichier de configuration interne, ne pas modifier                                                           
##############################################################################

## Récupération des disques disponibles    
LIST_DISK="$(lsblk -d -n | grep -v -e "loop" -e "sr" | awk '{print $1, $4}' | nl -s") ")" 