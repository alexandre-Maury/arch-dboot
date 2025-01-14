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

    local gpu_modules=""
    local has_multiple_gpus=false
                                               
    log_prompt "INFO" && echo " Installation des paquages de bases"

    arch-chroot ${MOUNT_POINT} pacman -Syu --noconfirm
    arch-chroot ${MOUNT_POINT} pacman -S --needed nano vim sudo pambase sshpass xdg-user-dirs git curl tar wget --noconfirm

    # CPU Microcode
    log_prompt "INFO" && echo " Installation du Microcode"
    
    if [[ "$PROC_UCODE" == "intel-ucode.img" ]]; then
        arch-chroot "${MOUNT_POINT}" pacman -S --needed intel-ucode --noconfirm
    elif [[ "$PROC_UCODE" == "amd-ucode.img" ]]; then
        arch-chroot "${MOUNT_POINT}" pacman -S --needed amd-ucode --noconfirm
    else
        log_prompt "INFO" && echo " Installation du microcode impossible"
    fi

    # Création des répertoires nécessaires
    mkdir -p "${MOUNT_POINT}/etc/modprobe.d"
    mkdir -p "${MOUNT_POINT}/etc/pacman.d/hooks"

    # Installation des paquets de base pour tous les systèmes
    arch-chroot "${MOUNT_POINT}" pacman -S --needed mesa vulkan-icd-loader lib32-vulkan-icd-loader --noconfirm

    # Configuration pour NVIDIA
    if echo "$GPU_VENDORS" | grep -q "nvidia"; then

        has_multiple_gpus=true
        gpu_modules="${gpu_modules:+$gpu_modules }nvidia nvidia_modeset nvidia_uvm nvidia_drm"
        
        # Installation des paquets NVIDIA
        arch-chroot "${MOUNT_POINT}" pacman -S --needed nvidia-dkms libglvnd nvidia-utils opencl-nvidia nvidia-settings lib32-nvidia-utils lib32-opencl-nvidia egl-wayland --noconfirm

        # Création du hook pacman
        {
            echo "[Trigger]" 
            echo "Operation=Install" 
            echo "Operation=Upgrade" 
            echo "Operation=Remove" 
            echo "Type=Package" 
            echo "Target=nvidia" 
            echo "Target=linux" 
            echo 
            echo "[Action]"
            echo "Description=Mise à jour du module nvidia dans initramfs"
            echo "Depends=mkinitcpio" 
            echo "When=PostTransaction"
            echo "NeedsTargets"
            echo "Exec=/usr/bin/mkinitcpio -P" 

        } > "${MOUNT_POINT}/etc/pacman.d/hooks/nvidia.hook"

        # Configuration modprobe NVIDIA
        {
            echo "options nvidia_drm modeset=1" 
            echo "options nvidia NVreg_UsePageAttributeTable=1" 
            echo "options nvidia NVreg_EnablePCIeGen3=1"
            echo "options nvidia NVreg_DynamicPowerManagement=0x02"
            echo "options nvidia_drm fbdev=1"
            
        } > "${MOUNT_POINT}/etc/modprobe.d/nvidia.conf"
    
    fi

    # Configuration pour AMD
    if echo "$GPU_VENDORS" | grep -q "amd\|radeon"; then
        has_multiple_gpus=true
        gpu_modules="${gpu_modules:+$gpu_modules }amdgpu radeon"
        
        # Installation des paquets AMD
        arch-chroot "${MOUNT_POINT}" pacman -S --needed xf86-video-amdgpu xf86-video-ati vulkan-radeon lib32-vulkan-radeon --noconfirm

        # Configuration modprobe AMD
        {
            echo "options amdgpu si_support=1" 
            echo "options amdgpu cik_support=1" 
            echo "options amdgpu modeset=1"
            echo "options amdgpu ppfeaturemask=0xffffffff"
            echo "options amdgpu dpm=1"
            
        } > "${MOUNT_POINT}/etc/modprobe.d/amdgpu.conf"

    fi

    # Configuration pour Intel
    if echo "$GPU_VENDORS" | grep -q "intel"; then
        has_multiple_gpus=true
        gpu_modules="${gpu_modules:+$gpu_modules }i915"
        
        # Installation des paquets Intel
        arch-chroot "${MOUNT_POINT}" pacman -S --needed xf86-video-intel vulkan-intel lib32-vulkan-intel intel-media-driver --noconfirm

        # Configuration modprobe Intel
        {
            echo "options i915 modeset=1" 
            echo "options i915 enable_guc=2" 
            echo "options i915 enable_fbc=1"
            echo "options i915 fastboot=1"
            echo "options i915 enable_psr=1"
            
        } > "${MOUNT_POINT}/etc/modprobe.d/i915.conf"

    fi

    # Si aucun GPU spécifique n'est détecté
    if [ -z "$gpu_modules" ]; then
        log_prompt "WARNING" && echo "GPU non reconnu, installation des pilotes génériques"
        arch-chroot "${MOUNT_POINT}" pacman -S --needed xf86-video-vesa --noconfirm
        gpu_modules="vesa"
    fi

    # Configuration pour systèmes multi-GPU
    if $has_multiple_gpus; then

        {
            echo "softdep nvidia pre: i915 amdgpu radeon" 
            echo "softdep i915 pre: amdgpu radeon" 
            
        } > "${MOUNT_POINT}/etc/modprobe.d/gpu-multi.conf"

    fi

    # Mise à jour de mkinitcpio.conf
    sed -i "s/^#\?MODULES=.*/MODULES=($gpu_modules)/" "${MOUNT_POINT}/etc/mkinitcpio.conf"

    if ! grep -q "^FILES=" "${MOUNT_POINT}/etc/mkinitcpio.conf"; then
        echo "FILES=(/etc/modprobe.d/*.conf /boot/$PROC_UCODE)" >> "${MOUNT_POINT}/etc/mkinitcpio.conf"
    else
        sed -i "s|^FILES=.*|FILES=(/etc/modprobe.d/*.conf /boot/$PROC_UCODE)|" "${MOUNT_POINT}/etc/mkinitcpio.conf"
    fi

    # Ajout du hook KMS
    if ! grep -q "kms" "${MOUNT_POINT}/etc/mkinitcpio.conf"; then
        sed -i 's/\(^HOOKS=.*\))/\1 kms)/' "${MOUNT_POINT}/etc/mkinitcpio.conf"
    fi

    # Régénération des initramfs pour tous les kernels installés
    for kernel in "${MOUNT_POINT}"/boot/vmlinuz-*; do
        if [ -f "$kernel" ]; then
            kernel_name=$(basename "$kernel" | sed 's/vmlinuz-//')
            arch-chroot "${MOUNT_POINT}" mkinitcpio -p "$kernel_name"
        fi
    done

    log_prompt "SUCCESS" && echo " mkinitcpio terminé avec succès."
}

install_bootloader() {

    clear
    
    local disk="$1"
    local disk_prefix=$(get_disk_prefix "$disk")
    local root_part=$(lsblk -n -o NAME,LABEL | grep "root" | awk '{print $1}' | sed "s/.*\(${disk}${disk_prefix}[0-9]*\)/\1/")
    local root_fs=$(blkid -s TYPE -o value /dev/${root_part})


    if [[ "$BOOTLOADER" == "grub" ]]; then

        log_prompt "INFO" && echo " arch-chroot - Installation de GRUB" 

        arch-chroot ${MOUNT_POINT} pacman -S --needed grub efibootmgr os-prober dosfstools mtools --noconfirm

        case "$root_fs" in
            "btrfs")
                arch-chroot ${MOUNT_POINT} pacman -S --needed btrfs-progs --noconfirm 
                ;;
        esac

        arch-chroot ${MOUNT_POINT} grub-install --target=x86_64-efi --efi-directory=/boot/EFI --bootloader-id=ArchLinux

        log_prompt "INFO" && echo "arch-chroot - configuration de grub"

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

        arch-chroot ${MOUNT_POINT} bootctl --path=/boot install

        {
            echo "default arch.conf"
            echo "timeout 10"
            echo "console-mode max"
            echo "editor no"

        } > "${MOUNT_POINT}/boot/loader/loader.conf"

        {
            echo "title   Arch Linux"
            echo "linux   /vmlinuz-linux"
            echo "initrd  /initramfs-linux.img"
            echo "options root=UUID=${root_uuid} rootflags=subvol=@ rw"

        } > "${MOUNT_POINT}/boot/loader/entries/arch.conf"

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

