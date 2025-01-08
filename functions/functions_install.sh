#!/bin/bash

# script functions_install.sh

install_base() {          

    clear

    echo
    log_prompt "INFO" && echo " Installation du système de base"
    reflector --country ${PAYS} --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    pacstrap -K ${MOUNT_POINT} base base-devel linux linux-headers linux-firmware dkms
}

config_system() {

    clear

    ## Generating the fstab                                                 
    log_prompt "INFO" && echo " Génération du fstab" 
    genfstab -U -p ${MOUNT_POINT} >> ${MOUNT_POINT}/etc/fstab

    ## Configuration du system                                                    
    log_prompt "INFO" && echo " Changement des makeflags pour " $CPU_COEUR " coeurs."

    if [[  $RAM -gt 8000000 ]]; then  # Vérifie si la mémoire totale est supérieure à 8 Go
        log_prompt "INFO" && echo " Changement des paramètres de compression pour " $CPU_COEUR " coeurs."

        sed -i "s/^#\?MAKEFLAGS=\".*\"/MAKEFLAGS=\"-j$CPU_COEUR\"/" "${MOUNT_POINT}/etc/makepkg.conf" # Modifie les makeflags dans makepkg.conf
        sed -i "s/^#\?COMPRESSXZ=(.*)/COMPRESSXZ=(xz -c -T $CPU_COEUR -z -)/" "${MOUNT_POINT}/etc/makepkg.conf" # Modifie les paramètres de compression

    fi

    ## Définir le fuseau horaire + local                                                  
    log_prompt "INFO" && echo " Configuration des locales"
    echo "KEYMAP=${KEYMAP}" > "${MOUNT_POINT}/etc/vconsole.conf"
    sed -i "/^#$LOCALE/s/^#//g" "${MOUNT_POINT}/etc/locale.gen"
    arch-chroot ${MOUNT_POINT} locale-gen
    
    echo " Configuration de la timezone..."
    ln -sf /usr/share/zoneinfo/${ZONE}/${CITY} "${MOUNT_POINT}/etc/localtime"
    hwclock --systohc

    echo "LANG=${LANG}" > "${MOUNT_POINT}/etc/locale.conf"

    ## Modification pacman.conf                                                  
    log_prompt "INFO" && echo " Modification du fichier pacman.conf"
    sed -i 's/^#Para/Para/' "${MOUNT_POINT}/etc/pacman.conf"
    sed -i "/\[multilib\]/,/Include/"'s/^#//' "${MOUNT_POINT}/etc/pacman.conf"
    arch-chroot ${MOUNT_POINT} pacman -Sy --noconfirm

    ## Configuration du réseau                                             
    log_prompt "INFO" && echo " Génération du hostname" 
    echo "${HOSTNAME}" > "${MOUNT_POINT}/etc/hostname"

    log_prompt "INFO" && echo " Génération du Host" 

    {
        echo "127.0.0.1 localhost"
        echo "::1 localhost"
        echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME"
    } > "${MOUNT_POINT}/etc/hosts"


    log_prompt "INFO" && echo " Configuration du fichier 20-wired.network" && echo

    {
        echo "[Match]"
        echo "Name=${INTERFACE}"
        echo "MACAddress=${MAC_ADDRESS}"
        echo
        echo "[Network]" 
        echo "DHCP=yes" 
        echo 
        echo "[DHCPv4]" 
        echo "RouteMetric=10" 
        echo "UseDNS=false" 
    } > "${MOUNT_POINT}/etc/systemd/network/20-wired.network"

    
    log_prompt "INFO" && echo " Configuration de /etc/resolv.conf pour utiliser systemd-resolved" && echo 
    ln -sf /run/systemd/resolve/stub-resolv.conf "${MOUNT_POINT}/etc/resolv.conf"

    log_prompt "INFO" && echo " Écrire la configuration DNS dans /etc/systemd/resolved.conf" && echo 

    {
        echo "[Resolve]" 
        echo "DNS=1.1.1.1 9.9.9.9" 
        echo "FallbackDNS=8.8.8.8"
    } > "${MOUNT_POINT}/etc/systemd/resolved.conf"

}

install_packages() {

    clear
                                               
    log_prompt "INFO" && echo " Installation des paquages de bases"
    arch-chroot ${MOUNT_POINT} pacman -Syu --noconfirm
    arch-chroot ${MOUNT_POINT} pacman -S --needed nano vim sudo pambase sshpass xdg-user-dirs git curl tar wget --noconfirm

    # CPU Microcode
    if [[ "$PROC_UCODE" == "intel-ucode.img" ]]; then
        arch-chroot "${MOUNT_POINT}" pacman -S --needed intel-ucode --noconfirm
    elif [[ "$PROC_UCODE" == "amd-ucode.img" ]]; then
        arch-chroot "${MOUNT_POINT}" pacman -S --needed amd-ucode --noconfirm
    else
        log_prompt "INFO" && echo " Installation du microcode impossible"
    fi

    # GPU Driver
    if [[ "$GPU_DRIVERS" == "nvidia" ]]; then
        arch-chroot "${MOUNT_POINT}" pacman -S --needed nvidia mesa --noconfirm

        [ ! -d "${MOUNT_POINT}/etc/pacman.d/hooks" ] && mkdir -p ${MOUNT_POINT}/etc/pacman.d/hooks

        {
            echo "[Trigger]" 
            echo "Operation=Install" 
            echo "Operation=Upgrade" 
            echo "Operation=Remove" 
            echo "Type=Package" 
            echo "Target=nvidia" 
            echo 
            echo "[Action]"
            echo "Depends=mkinitcpio" 
            echo "When=PostTransaction"
            echo "Exec=/usr/bin/mkinitcpio -P" 
        } > "${MOUNT_POINT}/etc/pacman.d/hooks/nvidia.hook"

    elif [[ "$GPU_DRIVERS" == "amd_radeon" ]]; then
        arch-chroot "${MOUNT_POINT}" pacman -S --needed xf86-video-amdgpu xf86-video-ati mesa --noconfirm 

    elif [[ "$GPU_DRIVERS" == "intel" ]]; then
        arch-chroot "${MOUNT_POINT}" pacman -S --needed xf86-video-intel mesa --noconfirm 

    else
        log_prompt "WARNING" && echo "GPU non-reconnu, installation des pilottes générique : xf86-video-vesa mesa"
        arch-chroot "${MOUNT_POINT}" pacman -S --needed xf86-video-vesa mesa --noconfirm

    fi

    sed -i 's/^#\?COMPRESSION="xz"/COMPRESSION="xz"/' "${MOUNT_POINT}/etc/mkinitcpio.conf"
    sed -i 's/^#\?COMPRESSION_OPTIONS=(.*)/COMPRESSION_OPTIONS=(-9e)/' "${MOUNT_POINT}/etc/mkinitcpio.conf"
    sed -i 's/^#\?MODULES_DECOMPRESS=".*"/MODULES_DECOMPRESS="yes"/' "${MOUNT_POINT}/etc/mkinitcpio.conf"
    sed -i "s/^#\?MODULES=.*/MODULES=($GPU_MODULES)/" "${MOUNT_POINT}/etc/mkinitcpio.conf"
    sed -i "s/^#\?MODULES=.*/MODULES=($GPU_MODULES)/" "${MOUNT_POINT}/etc/mkinitcpio.conf"
    sed -i "s/^#\?MODULES=.*/MODULES=($GPU_MODULES)/" "${MOUNT_POINT}/etc/mkinitcpio.conf"

}

install_bootloader() {

    clear
    
    local disk="$1"
    local root_part=$(lsblk -n -o NAME,LABEL | grep "root" | awk '{print $1}' | sed "s/.*\(${disk}[0-9]*\)/\1/")
    local root_fs=$(blkid -s TYPE -o value /dev/${root_part})


    if [[ "$BOOTLOADER" == "grub" ]]; then

        log_prompt "INFO" && echo " arch-chroot - Installation de GRUB" 

        arch-chroot ${MOUNT_POINT} pacman -S --needed grub efibootmgr os-prober dosfstools mtools --noconfirm

        case "$root_fs" in
            "btrfs")
                arch-chroot ${MOUNT_POINT} pacman -S --needed btrfs-progs --noconfirm 
                ;;
        esac

        arch-chroot ${MOUNT_POINT} grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch

        log_prompt "INFO" && echo "arch-chroot - configuration de grub"

        if [[ -n "${GPU_OPTION}" ]]; then
            sed -i -E "/^#?GRUB_CMDLINE_LINUX_DEFAULT=/ {s/^#//; /$GPU_OPTION/! s/(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)/\1 $GPU_OPTION/}" "${MOUNT_POINT}/etc/default/grub"
        fi

        sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' "${MOUNT_POINT}/etc/default/grub"

        log_prompt "INFO" && echo " arch-chroot - génération de grub.cfg"

        arch-chroot ${MOUNT_POINT} grub-mkconfig -o /boot/grub/grub.cfg

    fi

    if [[ "$BOOTLOADER" == "systemd-boot" ]]; then

        log_prompt "INFO" && echo " arch-chroot - Installation de systemd-boot" 

        arch-chroot ${MOUNT_POINT} pacman -S --needed efibootmgr os-prober dosfstools mtools --noconfirm

        case "$root_fs" in
            "btrfs")
                arch-chroot ${MOUNT_POINT} pacman -S --needed btrfs-progs --noconfirm 
                ;;
        esac

        root_uuid=$(blkid -s UUID -o value /dev/${root_part})
        root_options="root=UUID=${root_uuid} rootflags=subvol=@ rw"

        arch-chroot ${MOUNT_POINT} bootctl --path=/boot install

        {
            echo "title   Arch Linux"
            echo "linux   /vmlinuz-linux"
            echo "initrd  /${PROC_UCODE}"
            echo "initrd  /initramfs-linux.img"

            if [[ -n "${GPU_OPTION}" ]]; then
                echo "options ${root_options} $GPU_OPTION"
            else
                echo "options ${root_options}"
            fi
        } > "${MOUNT_POINT}/boot/loader/entries/arch.conf"

        {
            echo "title   Windows Boot Manager"
            echo "efi     /EFI/Microsoft/Boot/bootmgfw.efi"

        } > "${MOUNT_POINT}/boot/loader/entries/windows.conf"

        {
            echo "default arch.conf"
            echo "timeout 10"
            echo "console-mode max"
            echo "editor no"
        } > "${MOUNT_POINT}/boot/loader/loader.conf"

        clear

        # Détection automatique des entrées UEFI
        log_prompt "INFO" && echo " Recherche des entrées UEFI..."

        # Récupère toutes les entrées UEFI avec leurs identifiants
        all_boot=$(efibootmgr | grep -E '^Boot[0-9A-Fa-f]{4}\*')

        # Identifiant de l'entrée Windows Boot Manager
        windows_id=$(echo "$all_boot" | grep -i "Windows" | awk '{print $1}' | sed 's/Boot//;s/\*//')

        # Vérification si l'entrée Windows est trouvée
        if [[ -n "$windows_id" ]]; then
            log_prompt "INFO" && echo " Identifiant de l'entrée Windows : $windows_id"

            # Liste des autres entrées (hors Windows)
            other_ids=$(echo "$all_boot" | grep -v -i "Windows" | awk '{print $1}' | sed 's/Boot//;s/\*//')

            # Construction de l'ordre de démarrage
            new_boot_order=$(echo "$other_ids" | tr '\n' ',' | sed 's/,$//'),$windows_id

            # Affichage pour vérification
            log_prompt "INFO" && echo " Nouvel ordre de démarrage : $new_boot_order"

            # Application de l'ordre de démarrage
            efibootmgr -o $new_boot_order

            # Vérification finale
            log_prompt "INFO" && echo " Ordre de démarrage mis à jour :"
            echo
            efibootmgr
        fi
    fi
}

install_mkinitcpio() {

    log_prompt "INFO" && echo " Mise à jour du fichier mkinitcpio"

    arch-chroot "${MOUNT_POINT}" mkinitcpio -P | while IFS= read -r line; do
        echo "$line"
    done

    log_prompt "SUCCESS" && echo " mkinitcpio terminé avec succès."

}

config_passwdqc() {

    clear

    local passwdqc_conf="/etc/security/passwdqc.conf"
    local min_simple="4"     # Valeurs : disabled : Longueur minimale pour un mot de passe simple, c'est-à-dire uniquement des lettres minuscules (ex. : "abcdef").
    local min_2classes="4"   # Longueur minimale pour un mot de passe avec deux classes de caractères, par exemple minuscules + majuscules ou minuscules + chiffres (ex. : "Abcdef" ou "abc123").
    local min_3classes="4"   # Longueur minimale pour un mot de passe avec trois classes de caractères, comme minuscules + majuscules + chiffres (ex. : "Abc123").
    local min_4classes="4"   # Longueur minimale pour un mot de passe avec quatre classes de caractères, incluant minuscules + majuscules + chiffres + caractères spéciaux (ex. : "Abc123!").
    local min_phrase="4"     # Longueur minimale pour une phrase de passe, qui est généralement une suite de plusieurs mots ou une longue chaîne de caractères (ex. : "monmotdepassecompliqué").

    echo
    log_prompt "INFO" && echo " Configuration de passwdqc.conf" && echo ""
    if [ -f "${MOUNT_POINT}$passwdqc_conf" ]; then
        cp "${MOUNT_POINT}$passwdqc_conf" "${MOUNT_POINT}$passwdqc_conf.bak"
    fi

    echo
    log_prompt "INFO" && echo " Création ou modification du fichier passwdqc.conf dans ${MOUNT_POINT}${passwdqc_conf}" && echo 

    {
        echo "min=$min_simple,$min_2classes,$min_3classes,$min_4classes,$min_phrase"
        echo "max=72"
        echo "console-mode max"
        echo "editor no"
        echo "passphrase=3"
        echo "match=4"
        echo "similar=permit"
        echo "enforce=everyone"
        echo "retry=3"
    } > "${MOUNT_POINT}${passwdqc_conf}"

}

config_root() {

    ## arch-chroot Création d'un mot de passe root                                             
    while true; do
        echo
        log_prompt "PROMPT" && read -p " Souhaitez-vous changer le mot de passe du compte administrateur (Y/n) : " pass_root 
            
        # Vérifie la validité de l'entrée
        if [[ "$pass_root" =~ ^[yYnN]$ ]]; then
            break
        else
            echo
            log_prompt "WARNING" && echo " Veuillez répondre par Y (oui) ou N (non)." 
        fi
    done

    # Si l'utilisateur répond Y ou y
    if [[ "$pass_root" =~ ^[yY]$ ]]; then
        # Demande de changer le mot de passe root
        while true; do
            clear
            echo
            log_prompt "PROMPT" && read -p " Entrer le mot de passe pour le compte root : " -s new_pass 
            echo
            log_prompt "PROMPT" && read -p " Confirmez le mot de passe : " -s confirm_pass 

            # Vérifie si les mots de passe correspondent
            if [[ "$new_pass" == "$confirm_pass" ]]; then
                clear
                echo
                log_prompt "INFO" && echo "arch-chroot - Configuration du compte root"
                echo -e "$new_pass\n$new_pass" | arch-chroot ${MOUNT_POINT} passwd "root"
                break
            else
                echo
                log_prompt "WARNING" && echo " Les mots de passe ne correspondent pas. Veuillez réessayer." 
            fi
        done
    fi

}

config_user() {

    clear 

    ## arch-chroot Création d'un utilisateur + mot de passe                                            
    arch-chroot ${MOUNT_POINT} sed -i 's/# %wheel/%wheel/g' /etc/sudoers
    arch-chroot ${MOUNT_POINT} sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers

    # Demande tant que la réponse n'est pas y/Y ou n/N
    while true; do
        clear
        echo
        log_prompt "PROMPT" && read -p " Souhaitez-vous créer un utilisateur (Y/n) : " add_user 
            
        # Vérifie la validité de l'entrée
        if [[ "$add_user" =~ ^[yYnN]$ ]]; then
            break
        else
            echo
            log_prompt "WARNING" && echo " Veuillez répondre par Y (oui) ou N (non)."
        fi
    done

    # Si l'utilisateur répond Y ou y
    if [[ "$add_user" =~ ^[yY]$ ]]; then
        clear
        echo
        log_prompt "PROMPT" && read -p " Saisir le nom d'utilisateur souhaité : " sudo_user
        arch-chroot ${MOUNT_POINT} useradd -m -G wheel,audio,video,optical,storage,power,input "$sudo_user"

        # Demande de changer le mot de passe $USER
        while true; do
            clear
            echo
            log_prompt "PROMPT" && read -p " Entrer le mot de passe pour le compte $sudo_user : " -s new_pass  
            echo
            log_prompt "PROMPT" && read -p " Confirmez le mot de passe : " -s confirm_pass  

            # Vérifie si les mots de passe correspondent
            if [[ "$new_pass" == "$confirm_pass" ]]; then
                clear
                echo
                log_prompt "INFO" && echo " arch-chroot - Configuration du compte $sudo_user"
                echo -e "$new_pass\n$new_pass" | arch-chroot ${MOUNT_POINT} passwd $sudo_user
                break
            else
                echo
                log_prompt "WARNING" && echo " Les mots de passe ne correspondent pas. Veuillez réessayer."
            fi
        done
    fi
}

config_ssh() {

    clear

    local ssh_config_file="/etc/ssh/sshd_config"

    echo
    log_prompt "INFO" && echo " arch-chroot - Configuration du SSH"
    echo
    sed -i "s/#Port 22/Port $SSH_PORT/" "${MOUNT_POINT}$ssh_config_file"
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' "${MOUNT_POINT}$ssh_config_file"
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' "${MOUNT_POINT}$ssh_config_file"
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' "${MOUNT_POINT}$ssh_config_file"
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' "${MOUNT_POINT}$ssh_config_file"

}

activate_service() {
    clear
    echo
    log_prompt "INFO" && echo " arch-chroot - Activation des services"
    echo
    arch-chroot ${MOUNT_POINT} systemctl enable sshd
    arch-chroot ${MOUNT_POINT} systemctl enable systemd-homed
    arch-chroot ${MOUNT_POINT} systemctl enable systemd-networkd 
    arch-chroot ${MOUNT_POINT} systemctl enable systemd-resolved 
}

