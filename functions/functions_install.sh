#!/bin/bash

# script functions_install.sh

install_base() {

    local disk="$1"
    local interface="$(ip link show | awk -F': ' '/^[0-9]+: / && !/lo/ {print $2; exit}')"
    local mac_address=$(ip link | awk '/ether/ {print $2; exit}')
    local nc=$(grep -c ^processor /proc/cpuinfo)  # Compte le nombre de cœurs de processeur
    local total_mem=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')  # Récupère la mémoire totale
                                      
    clear
    log_prompt "INFO" && echo "Installation du système de base"
    reflector --country ${PAYS} --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    pacstrap -K ${MOUNT_POINT} base base-devel linux linux-headers linux-firmware dkms

    ## Generating the fstab                                                 
    log_prompt "INFO" && echo "Génération du fstab" 
    genfstab -U -p ${MOUNT_POINT} >> ${MOUNT_POINT}/etc/fstab

    ## Configuration du system                                                    
    log_prompt "INFO" && echo "Changement des makeflags pour " $nc " coeurs."

    if [[  $total_mem -gt 8000000 ]]; then  # Vérifie si la mémoire totale est supérieure à 8 Go
        log_prompt "INFO" && echo "Changement des paramètres de compression pour " $nc " coeurs."

        sed -i "s/^#\?MAKEFLAGS=\".*\"/MAKEFLAGS=\"-j$nc\"/" ${MOUNT_POINT}/etc/makepkg.conf # Modifie les makeflags dans makepkg.conf
        sed -i "s/^#\?COMPRESSXZ=(.*)/COMPRESSXZ=(xz -c -T $nc -z -)/" ${MOUNT_POINT}/etc/makepkg.conf # Modifie les paramètres de compression

    fi

    ## Définir le fuseau horaire + local                                                  
    log_prompt "INFO" && echo "Configuration des locales"
    echo "KEYMAP=${KEYMAP}" > ${MOUNT_POINT}/etc/vconsole.conf
    sed -i "/^#$LOCALE/s/^#//g" ${MOUNT_POINT}/etc/locale.gen
    arch-chroot ${MOUNT_POINT} locale-gen
    
    echo "Configuration de la timezone..."
    ln -sf /usr/share/zoneinfo/${ZONE}/${CITY} ${MOUNT_POINT}/etc/localtime
    hwclock --systohc

    echo "LANG=${LANG}" > ${MOUNT_POINT}/etc/locale.conf # AJOUT

    ## Modification pacman.conf                                                  
    log_prompt "INFO" && echo "Modification du fichier pacman.conf"
    sed -i 's/^#Para/Para/' ${MOUNT_POINT}/etc/pacman.conf
    sed -i "/\[multilib\]/,/Include/"'s/^#//' ${MOUNT_POINT}/etc/pacman.conf
    arch-chroot ${MOUNT_POINT} pacman -Sy --noconfirm

    ## Configuration du réseau                                             
    log_prompt "INFO" && echo "Génération du hostname" 
    echo "${HOSTNAME}" > ${MOUNT_POINT}/etc/hostname

    log_prompt "INFO" && echo "Génération du Host" 

    {
        echo "127.0.0.1 localhost"
        echo "::1 localhost"
        echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME"
    } > ${MOUNT_POINT}/etc/hosts


    log_prompt "INFO" && echo "Configuration du fichier 20-wired.network dans ${MOUNT_POINT}/etc/systemd/network" && echo

    {
        echo "[Match]"
        echo "Name=${interface}"
        echo "MACAddress=${mac_address}"
        echo
        echo "[Network]" 
        echo "DHCP=yes" 
        echo 
        echo "[DHCPv4]" 
        echo "RouteMetric=10" 
        echo "UseDNS=false" 
    } > ${MOUNT_POINT}/etc/systemd/network/20-wired.network

    
    log_prompt "INFO" && echo "Configuration de /etc/resolv.conf pour utiliser systemd-resolved" && echo 
    ln -sf /run/systemd/resolve/stub-resolv.conf "${MOUNT_POINT}/etc/resolv.conf"

    log_prompt "INFO" && echo "Écrire la configuration DNS dans /etc/systemd/resolved.conf" && echo 

    {
        echo "[Resolve]" 
        echo "DNS=1.1.1.1 9.9.9.9" 
        echo "FallbackDNS=8.8.8.8"
    } > ${MOUNT_POINT}/etc/systemd/resolved.conf


}

install_base_chroot() {
    
    local disk="$1"
    local gpu_vendor=$(lspci | grep -i "VGA\|3D" | awk '{print tolower($0)}')
    local root_part=$(lsblk -n -o NAME,LABEL | grep "root" | awk '{print $1}' | sed "s/.*\(${disk}[0-9]*\)/\1/")
    local root_fs=$(blkid -s TYPE -o value /dev/${root_part})
    local cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')

    local proc_ucode
    local modules
    local kernel_option

    ## Chroot install packages                                                
    log_prompt "INFO" && echo "Installation des paquages de bases"
    arch-chroot ${MOUNT_POINT} pacman -Syu --noconfirm
    arch-chroot ${MOUNT_POINT} pacman -S man-db man-pages nano vim sudo pambase sshpass xdg-user-dirs git curl tar wget --noconfirm

    # Détection du type de processeur
    case "$cpu_vendor" in
        "GenuineIntel")
            proc_ucode="intel-ucode.img"
            arch-chroot ${MOUNT_POINT} pacman -S intel-ucode --noconfirm
            ;;
        "AuthenticAMD")
            proc_ucode="amd-ucode.img"
            arch-chroot ${MOUNT_POINT} pacman -S amd-ucode --noconfirm
            ;;
        *)
            log_prompt "ERROR" && echo "Vendor CPU non reconnu: $cpu_vendor"
            proc_ucode=""
            ;;
    esac


    ## Installation des pilotes GPU                                          
    if [[ "$gpu_vendor" == *"nvidia"* ]]; then
        log_prompt "INFO" && echo "arch-chroot - Configuration pour GPU NVIDIA"
        modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
        kernel_option="nvidia_drm.modeset=1"
        arch-chroot "${MOUNT_POINT}" pacman -S nvidia mesa --noconfirm
        modprobe $modules

        sed -i "s/^#\?MODULES=.*/MODULES=($modules)/" ${MOUNT_POINT}/etc/mkinitcpio.conf

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
        } > ${MOUNT_POINT}/etc/pacman.d/hooks/nvidia.hook


    elif [[ "$gpu_vendor" == *"amd"* || "$gpu_vendor" == *"radeon"* ]]; then
        log_prompt "INFO" && echo "arch-chroot - Configuration pour GPU AMD/Radeon"
        modules="amdgpu"
        kernel_option="amdgpu.dc=1"
        arch-chroot "${MOUNT_POINT}" pacman -S xf86-video-amdgpu xf86-video-ati mesa --noconfirm 
        modprobe $modules

        sed -i "s/^#\?MODULES=.*/MODULES=($modules)/" ${MOUNT_POINT}/etc/mkinitcpio.conf

    elif [[ "$gpu_vendor" == *"intel"* ]]; then
        log_prompt "INFO" && echo "arch-chroot - Configuration pour GPU Intel"
        modules="i915"
        kernel_option="i915.enable_psr=1"
        arch-chroot "${MOUNT_POINT}" pacman -S xf86-video-intel mesa --noconfirm 
        modprobe $modules

        sed -i "s/^#\?MODULES=.*/MODULES=($modules)/" ${MOUNT_POINT}/etc/mkinitcpio.conf

    else
        log_prompt "WARNING" && echo "arch-chroot - Aucun GPU reconnu, installation des pilottes générique : xf86-video-vesa mesa"
        arch-chroot "${MOUNT_POINT}" pacman -S xf86-video-vesa mesa --noconfirm
    fi

    sed -i 's/^#\?COMPRESSION="xz"/COMPRESSION="xz"/' "${MOUNT_POINT}/etc/mkinitcpio.conf"
    sed -i 's/^#\?COMPRESSION_OPTIONS=(.*)/COMPRESSION_OPTIONS=(-9e)/' "${MOUNT_POINT}/etc/mkinitcpio.conf"
    sed -i 's/^#\?MODULES_DECOMPRESS=".*"/MODULES_DECOMPRESS="yes"/' "${MOUNT_POINT}/etc/mkinitcpio.conf"

    arch-chroot "${MOUNT_POINT}" mkinitcpio -P | while IFS= read -r line; do
        echo "$line"
    done

    echo "mkinitcpio terminé avec succès."

    arch-chroot ${MOUNT_POINT} pacman -S btrfs-progs efibootmgr os-prober --noconfirm 
    root_uuid=$(blkid -s UUID -o value /dev/${root_part})
    root_options="root=UUID=${root_uuid} rootflags=subvol=@ rw"

    # arch-chroot ${MOUNT_POINT} bootctl --path=/boot install
    arch-chroot ${MOUNT_POINT} bootctl --esp-path=/boot --boot-path=/boot install

    {
        echo "title   Arch Linux"
        echo "linux   /vmlinuz-linux"
        echo "initrd  /${proc_ucode}"
        echo "initrd  /initramfs-linux.img"

        if [[ -n "${kernel_option}" ]]; then
            echo "options ${root_options} $kernel_option"
        else
            echo "options ${root_options}"
        fi
    } > ${MOUNT_POINT}/boot/loader/entries/arch.conf

    {
        echo "default arch.conf"
        echo "timeout 4"
        echo "console-mode max"
        echo "editor no"
    } > ${MOUNT_POINT}/boot/loader/loader.conf

}

install_base_secu() {

    local passwdqc_conf="/etc/security/passwdqc.conf"
    local min_simple="4"     # Valeurs : disabled : Longueur minimale pour un mot de passe simple, c'est-à-dire uniquement des lettres minuscules (ex. : "abcdef").
    local min_2classes="4"   # Longueur minimale pour un mot de passe avec deux classes de caractères, par exemple minuscules + majuscules ou minuscules + chiffres (ex. : "Abcdef" ou "abc123").
    local min_3classes="4"   # Longueur minimale pour un mot de passe avec trois classes de caractères, comme minuscules + majuscules + chiffres (ex. : "Abc123").
    local min_4classes="4"   # Longueur minimale pour un mot de passe avec quatre classes de caractères, incluant minuscules + majuscules + chiffres + caractères spéciaux (ex. : "Abc123!").
    local min_phrase="4"     # Longueur minimale pour une phrase de passe, qui est généralement une suite de plusieurs mots ou une longue chaîne de caractères (ex. : "monmotdepassecompliqué").
    local ssh_config_file="/etc/ssh/sshd_config"

    log_prompt "INFO" && echo "Configuration de passwdqc.conf" && echo ""
    if [ -f "${MOUNT_POINT}$passwdqc_conf" ]; then
        cp "${MOUNT_POINT}$passwdqc_conf" "${MOUNT_POINT}$passwdqc_conf.bak"
    fi

    log_prompt "INFO" && echo "Création ou modification du fichier passwdqc.conf dans ${MOUNT_POINT}${passwdqc_conf}" && echo 

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
    } > ${MOUNT_POINT}${passwdqc_conf}

    ## arch-chroot Création d'un mot de passe root                                             
    while true; do
        log_prompt "INFO" && read -p "Souhaitez-vous changer le mot de passe root (Y/n) : " pass_root 
            
        # Vérifie la validité de l'entrée
        if [[ "$pass_root" =~ ^[yYnN]$ ]]; then
            break
        else
            log_prompt "WARNING" && echo "Veuillez répondre par Y (oui) ou N (non)." 
        fi
    done

    # Si l'utilisateur répond Y ou y
    if [[ "$pass_root" =~ ^[yY]$ ]]; then
        # Demande de changer le mot de passe root
        while true; do
            clear
            read -p "Veuillez entrer le nouveau mot de passe pour root : " -s new_pass 
            echo
            read -p "Confirmez le mot de passe : " -s confirm_pass 

            # Vérifie si les mots de passe correspondent
            if [[ "$new_pass" == "$confirm_pass" ]]; then
                log_prompt "INFO" && echo "arch-chroot - Configuration du compte root"
                echo -e "$new_pass\n$new_pass" | arch-chroot ${MOUNT_POINT} passwd "root"
                break
            else
                log_prompt "WARNING" && echo "Les mots de passe ne correspondent pas. Veuillez réessayer." 
            fi
        done
    fi

        ## arch-chroot Création d'un utilisateur + mot de passe                                            
    arch-chroot ${MOUNT_POINT} sed -i 's/# %wheel/%wheel/g' /etc/sudoers
    arch-chroot ${MOUNT_POINT} sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers

    # Demande tant que la réponse n'est pas y/Y ou n/N
    while true; do
        log_prompt "INFO" && read -p "Souhaitez-vous créer un utilisateur (Y/n) : " add_user 
            
        # Vérifie la validité de l'entrée
        if [[ "$add_user" =~ ^[yYnN]$ ]]; then
            break
        else
            log_prompt "WARNING" && echo "Veuillez répondre par Y (oui) ou N (non)."
        fi
    done

    # Si l'utilisateur répond Y ou y
    if [[ "$add_user" =~ ^[yY]$ ]]; then
        log_prompt "INFO" && read -p "Saisir le nom d'utilisateur souhaité : " sudo_user
        arch-chroot ${MOUNT_POINT} useradd -m -G wheel,audio,video,optical,storage,power,input "$sudo_user"

        # Demande de changer le mot de passe $USER
        while true; do
            clear
            read -p "Veuillez entrer le nouveau mot de passe pour $sudo_user : " -s new_pass  
            echo
            read -p "Confirmez le mot de passe : " -s confirm_pass  

            # Vérifie si les mots de passe correspondent
            if [[ "$new_pass" == "$confirm_pass" ]]; then
                log_prompt "INFO" && echo "arch-chroot - Configuration du compte $sudo_user"
                echo -e "$new_pass\n$new_pass" | arch-chroot ${MOUNT_POINT} passwd $sudo_user
                break
            else
                log_prompt "WARNING" && echo "Les mots de passe ne correspondent pas. Veuillez réessayer."
            fi
        done
    fi

    log_prompt "INFO" && echo "arch-chroot - Configuration du SSH"
    sed -i "s/#Port 22/Port $SSH_PORT/" "${MOUNT_POINT}$ssh_config_file"
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' "${MOUNT_POINT}$ssh_config_file"
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' "${MOUNT_POINT}$ssh_config_file"
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' "${MOUNT_POINT}$ssh_config_file"
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' "${MOUNT_POINT}$ssh_config_file"

}

activate_service() {
    clear
    log_prompt "INFO" && echo "arch-chroot - Activation des services"
    arch-chroot ${MOUNT_POINT} systemctl enable sshd
    arch-chroot ${MOUNT_POINT} systemctl enable systemd-homed
    arch-chroot ${MOUNT_POINT} systemctl enable systemd-networkd 
    arch-chroot ${MOUNT_POINT} systemctl enable systemd-resolved 
}

