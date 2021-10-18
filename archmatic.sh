#!/usr/bin/env sh

#-------------------------------------------------------------------------
#   Maintainer: Nelox
#   Description: Custom Arch Installation and Config Script
#   License: GPLv3
#-------------------------------------------------------------------------

function preinstall {
    # UEFI / BIOS detection
    efivar -l >/dev/null 2>&1
       
    if [[ $? -eq 0 ]]; then
        echo "UEFI detected. Installation will go on."
    else
        echo ="BIOS detected. This Installation Script is for UEFI only! Execution aborted."
        exit
    fi

    # check ethernet connection
    ping -c3 archlinux.org

    if [ $? -eq 0 ]; then
        echo "Internet connection detected. Installation will go on."
    else
        echo ="Internet connection failed. Execution aborted."
        exit
    fi

    # sync systemclock
    timedatectl set-ntp true
    timedatectl status

    # Set-up mirrors for optimal download
    reflector --verbose --country 'Germany' -l 5 -p https --sort rate --save /etc/pacman.d/mirrorlist

    # Prompts

    lsblk

    echo -e "\nEnter your drive: /dev/sda, /dev/nvme0n1, etc."
    read disk

    # Define disk variables for sda, sdb, sdc, nvme0n1, nvme0n2 or nvme0n3.
    if [ "${disk}" == "/dev/nvme0n1" ]; then
        disk_boot="${disk}p1"
        disk_esp="${disk}p2"
        disk_lvm="${disk}p3"
        disk_lvm_sed="\/dev\/nvme0n1p3"
    fi

    if [ "${disk}" == "/dev/nvme0n2" ]; then
        disk_boot="${disk}p1"
        disk_esp="${disk}p2"
        disk_lvm="${disk}p3"
        disk_lvm_sed="\/dev\/nvme0n2p3"
    fi

    if [ "${disk}" == "/dev/nvme0n3" ]; then
        disk_boot="${disk}p1"
        disk_esp="${disk}p2"
        disk_lvm="${disk}p3"
        disk_lvm_sed="\/dev\/nvme0n3p3"
    fi

    if [ "${disk}" == "/dev/sda" ]; then
        disk_boot="${disk}1"
        disk_esp="${disk}2"
        disk_lvm="${disk}3"
        disk_lvm_sed="\/dev\/sda3"
    fi

    if [ "${disk}" == "/dev/sdb" ]; then
        disk_boot="${disk}1"
        disk_esp="${disk}2"
        disk_lvm="${disk}3"
        disk_lvm_sed="\/dev\/sdb3"
    fi

    if [ "${disk}" == "/dev/sdc" ]; then
        disk_boot="${disk}1"
        disk_esp="${disk}2"
        disk_lvm="${disk}3"
        disk_lvm_sed="\/dev\/sdc3"
    fi

    echo -e "\nSet hostname:"
    read hostname

    echo -e "\nSet ROOT password:"
    read -s root_password

    echo -e "\nVerify ROOT password:"
    read -s root_password2

    # Check if both passwords match
    if [ "${root_password}" != "${root_password2}" ]; then
        echo "Passwords do not match!"
        exit
    fi

    echo -e "\nSet username:"
    read user

    echo -e "\nSet USER password:"
    read -s user_password

    echo -e "\nVerify USER password:"
    read -s user_password2

    # Check if both passwords match
    if [ "${user_password}" != "${user_password2}" ]; then
        echo "Passwords do not match!"
        exit
    fi

    echo -e "\nInstall Desktop Environment: [gnome/kde/none]"
    read de

    echo -e "\n8GB Swapfile: [y/N]"
    read swap

    echo -e "\nLaptop power management package: [y/N]"
    read laptop

    echo -e "\nBluetooth packages: [y/N]"
    read bluetooth

    echo -e "\nWi-Fi packages: [y/N]"
    read wifi

    echo -e "\nSelect your CPU: [amd/intel/vbox]"
    read ucode

    # export environment variabels
    export disk
    export disk_boot
    export disk_esp
    export disk_lvm
    export disk_lvm_sed
    export hostname
    export root_password
    export user
    export user_password
    export de
    export swap
    export laptop
    export bluetooth
    export wifi
    export ucode
}

function baseInstall {
    # Format disk

    # Disk prep
    sgdisk -Z ${disk}             # zap all on disk
    sgdisk -a 2048 -o ${disk}     # new gpt disk 2048 alignment

    # Create partition layout
    sgdisk -n 1:0:+1024M ${disk}  # partition 1 (boot), default start block, size: 1024MB
    sgdisk -n 2:0:+1024M ${disk}  # partition 2 (esp), default start block, size: 1024MB
    sgdisk -n 3:0:0 ${disk}       # partition 3 (lvm), default start, size: remaining space

    # Set partition types
    sgdisk -t 1:8300 ${disk}
    sgdisk -t 2:ef00 ${disk}
    sgdisk -t 3:8e00 ${disk}

    # Label partitions
    sgdisk -c 1:"boot" ${disk}
    sgdisk -c 2:"esp" ${disk}
    sgdisk -c 3:"lvm" ${disk}

    # Load kernel module for cryptsetup
    modprobe dm-crypt

    # Create LUKS encrypted lvm partition
    cryptsetup luksFormat -c aes-xts-plain64 -y -s 512 -h sha512 ${disk_lvm}
    cryptsetup luksOpen ${disk_lvm} lvm

    # Set-up lvm
    pvcreate /dev/mapper/lvm
    vgcreate vg0 /dev/mapper/lvm
    lvcreate -l 100%FREE -n lv_root vg0

    # Scan for vgs and activate them all
    vgscan
    vgchange -ay

    # Create filesystem
    mkfs.ext4 ${disk_boot}
    mkfs.fat -F32 ${disk_esp}
    mkfs.ext4 /dev/vg0/lv_root

    # Mount target
    mount /dev/vg0/lv_root /mnt
    mkdir /mnt/boot
    mount ${disk_boot} /mnt/boot
    mkdir /mnt/boot/esp
    mount ${disk_esp} /mnt/boot/esp

    # Generate /etc/fstab
    mkdir /mnt/etc
    genfstab -Up /mnt >> /mnt/etc/fstab

    # Install basic packages
    pacstrap /mnt base base-devel linux linux-firmware linux-headers grub efibootmgr os-prober dosfstools mtools lvm2 --noconfirm --needed

    # Install basic Networking tools
    pacstrap /mnt networkmanager --noconfirm --needed

    arch-chroot /mnt /bin/bash <<"CHROOT"
        
        # Enable NetworkManager
        systemctl enable NetworkManager
        
        # Set root password
        echo "root:${root_password}" | chpasswd

        ### Bootloader
        ## Reduce grub delay on boot
        sed -i -e 's|GRUB_TIMEOUT=5|GRUB_TIMEOUT=0|g' /etc/default/grub

        # ${disk_lvm_sed} is needed because of the slashes in ${disk_lvm}, that need to be escaped
        sed -i -e "s|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"|GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=${disk_lvm_sed}:vg0:allow-discards loglevel=3\"|g" /etc/default/grub

        # Enable encrypted boot
        sed -i -e 's|#GRUB_ENABLE_CRYPTODISK=y|GRUB_ENABLE_CRYPTODISK=y|g' /etc/default/grub

        # Install grub
        grub-install --target=x86_64-efi --efi-directory=/boot/esp --bootloader-id=grub_uefi --recheck --debug
        # Copy the locale file to locale directory
        cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
        # Generate GRUB's config file
        grub-mkconfig -o /boot/grub/grub.cfg

        # Update initial ramdisk
        sed -i -e 's|HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)|HOOKS=(base udev autodetect modconf block encrypt lvm2 filesystems keyboard fsck)|g' /etc/mkinitcpio.conf
        mkinitcpio -p linux
CHROOT
}

function baseSetup {
    arch-chroot /mnt /bin/bash <<"CHROOT"

        # Set locales
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
        echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
        locale-gen
        echo "LANG=de_DE.UTF-8 UTF-8" >> /etc/locale.conf

        # Set time zone
        ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime

        # Specify cores for simultaneous compiling
        sudo sed -i "s|#MAKEFLAGS=\"-j2\"|MAKEFLAGS=\"-j$(nproc)\"|g" /etc/makepkg.conf
        # Change compression settings for "$nproc" cores.
        sudo sed -i "s|COMPRESSXZ=(xz -c -z -)|COMPRESSXZ=(xz -c -T $(nproc) -z -)|g" /etc/makepkg.conf

        # Parallel downloading (since pacman v6)
        sed -i 's/^#Para/Para/' /etc/pacman.conf

        # Set hostname
        echo ${hostname} > /etc/hostname

        # Configure hosts file
        echo "127.0.1.1 ${hostname}" >> /etc/hosts

        # Set-up user account
        useradd -m -G users,wheel -s /bin/bash ${user}
        echo "${user}:${user_password}" | chpasswd

        # Enable sudo-privileges for group "wheel"
        sed -i 's|# %wheel ALL=(ALL) ALL|%wheel ALL=(ALL) ALL|' /etc/sudoers

        # Set-up 8GB swapfile
        if [ "${swap}" == "y" ]; then
            dd if=/dev/zero of=/swapfile bs=1M count=8192 status=progress
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            echo '/swapfile none swap defaults 0 0' >> /etc/fstab
        fi

        # Install CPU Microcode files
        pacman -S ${ucode}-ucode --noconfirm --needed
CHROOT
}


function softwareDesk {
    arch-chroot /mnt /bin/bash <<"CHROOT"

        ### Official repo packages
        
        PKGS=(
            # DISPLAY RENDERING -------------------------------------------------------------
            'xorg-drivers'              # Display Drivers
            'xorg-xlsclients'           # Temp: Wayland Support
            'xorg-xwayland'             # Temp: Wayland Support
            'qt5-wayland'               # Temp: Wayland Support
            'glfw-wayland'              # Temp: Wayland Support
            'mesa'                      # Open source version of OpenGL

            # NETWORK SETUP ----------------------------------------------------------------------
            'openvpn'                   # Open VPN support
            'networkmanager-openvpn'    # Open VPN plugin for NM
            'network-manager-applet'    # System tray icon/utility for network connectivity

            # AUDIO ------------------------------------------------------------------------------
            'pipewire'                  # Temp: Pipewire Support
            'pipewire-alsa'             # Temp: Pipewire Support
            'pipewirde-pulse'           # Temp: Pipewire Support
            'alsa-utils'                # Advanced Linux Sound Architecture (ALSA) Components https://alsa.opensrc.org/
            #'alsa-plugins'             # ALSA plugins
            #'pulseaudio'               # Pulse Audio sound components
            #'pulseaudio-alsa'          # ALSA configuration for pulse audio
            #'pavucontrol'              # Pulse Audio volume control
            #'pnmixer'                  # System tray volume control

            # PRINTERS ---------------------------------------------------------------------------
            'cups'                      # Open source printer drivers
            'cups-pdf'                  # PDF support for cups
            'ghostscript'               # PostScript interpreter
            'gsfonts'                   # Adobe Postscript replacement fonts
            'hplip'                     # HP Drivers
            'system-config-printer'     # Printer setup  utility

            # TERMINAL UTILITIES -----------------------------------------------------------------
            'zsh'                       # ZSH shell
            'zsh-completions'           # Tab completion for ZSH
            'zsh-autosuggestions'       # History-based suggestions
            'zsh-syntax-highlighting'   # ZSH Syntax highlighting
            'cronie'                    # cron jobs
            'curl'                      # Remote content retrieval
            'wget'                      # Remote content retrieval
            'htop'                      # Process viewer
            'hardinfo'                  # Hardware info app
            'neofetch'                  # Shows system info when you launch terminal
            'numlockx'                  # Turns on numlock in X11
            'openssh'                   # SSH connectivity tools
            'p7zip'                     # 7z compression program
            'rsync'                     # Remote file sync utility
            'speedtest-cli'             # Internet speed via terminal
            'unrar'                     # RAR compression program
            'unzip'                     # Zip compression program
            'vim'                       # Text Editor
            'nano'                      # Text Editor
            'reflector'                  # Tool for fetching latest mirrors

            # DISK UTILITIES ---------------------------------------------------------------------
            'android-tools'             # ADB for Android
            'autofs'                    # Auto-mounter
            'dosfstools'                # DOS Support
            'exfat-utils'               # Mount exFat drives
            'filezilla'                  # SSH File Transfer
            'balena-etcher'             # Bootable USB Creator

            # GENERAL UTILITIES ------------------------------------------------------------------
            'freerdp'                   # RDP Connections
            'libvncserver'              # VNC Connections
            'remmina'                   # Remote Connection
            'veracrypt'                 # Disc encryption utility
            'keepassxc'                 # Password Manager
            'syncthing'                 # Encrypted File Sync
            'qbittorrent'               # Great Torrent Client
   
            # DEVELOPMENT ------------------------------------------------------------------------
            'hugo'                      # Framework for creating light Webpages
            'grub-customizer'           # Graphical grub2 settings manager
            'clang'                     # C Lang compiler
            'cmake'                     # Cross-platform open-source make system
            'electron'                  # Cross-platform development using Javascript
            'git'                       # Version control system
            'gcc'                       # C/C++ compiler
            'glibc'                     # C libraries
            'meld'                      # File/directory comparison
            'nodejs'                    # Javascript runtime environment
            'npm'                       # Node package manager
            'python'                    # Scripting language
            'yarn'                      # Dependency management (Hyper needs this)
            'go'                        # Import programming language

            # MEDIA ------------------------------------------------------------------------------
            'obs-studio'                # Record your screen
            'vlc'                       # Video player

            # GRAPHICS AND DESIGN ----------------------------------------------------------------
            'gimp'                      # GNU Image Manipulation Program
            'papirus-icon-theme'        # Papirus Icon Theme for KDE/GNOME

            # BROWSER ----------------------------------------------------------------------------
            'firefox'                    # Browser
            'torbrowser-launcher'       # Onion Routing

            # COMMUNICATION ----------------------------------------------------------------------
            'thunderbird'               # Mail Client
            'element-desktop'           # Matrix Client for Communication
            'signal-desktop'            # Signal Desktop Communication Client
            'discord'                   # Not recommendable proprietary Communication System

            # OFFICE -----------------------------------------------------------------------------
            'libreoffice'                 # Office Suite
        )
        for PKG in "${PKGS[@]}"; do
        pacman -S ${PKG} --noconfirm --needed
        done
            
            
        ### Desktop Environment

        ## KDE
            
        if [ "${de}" == "kde" ]; then
            PKGS=(
                # Plasma -----------------------------------------------------------------------------
                'plasma-meta'               # Desktop Environment
                'kde-applications-meta'     # KDE Applications
                'plasma-wayland-session'    # Support for wayland session
                'packagekit-qt5'            # Discover Back-end for standard arch repos
                'xdg-user-dirs'             # Create user directories in Dolphin
                'sddm'                      # Login Manager
            )
            for PKG in "${PKGS[@]}"; do
            pacman -S ${PKG} --noconfirm --needed
            done

            PKGS=(               
                # Remove unnecessary packages, that came as dependencies
                'kde-education-meta'
                'kde-games-meta'
                'kde-multimedia-meta'
            )
            for PKG in "${PKGS[@]}"; do
            pacman -R ${PKG} --noconfirm --needed
            done
        fi

        ## GNOME

        if [ "${de}" == "gnome" ]; then
            PKGS=(
                # GNOME --------------------------------------------------------------------------------
                'gnome'                     # Desktop Environment
                'gdm'                       # Login Manager
                'gnome-tweaks'              # GNOME tweaking tool
                'seahorse'                  # SSH/PGP management front-end
            )
            for PKG in "${PKGS[@]}"; do
            pacman -S ${PKG} --noconfirm --needed
            done

            PKGS=(
                # Remove unnecessary packages, that came as dependencies
                'epiphany'                     # GNOME Browser
            )
            for PKG in "${PKGS[@]}"; do
            pacman -S ${PKG} --noconfirm --needed
            done
        fi

        ### Laptop power management
            
        if [ "${laptop}" == "y" ]; then
            PKGS=(
                # OTHERS -----------------------------------------------------------------------------
                'tlp'                       # Advanced laptop power management
            )
            for PKG in "${PKGS[@]}"; do
            pacman -S ${PKG} --noconfirm --needed
            done
        fi

        ### Bluetooth

        if [ "${bluetooth}" == "y" ]; then
            PKGS=(
                # BLUETOOTH --------------------------------------------------------------------------
                'bluez'                     # Daemons for the bluetooth protocol stack
                'bluez-utils'               # Bluetooth development and debugging utilities
                'bluez-firmware'            # Firmwares for Broadcom BCM203x and STLC2300 Bluetooth chips
                'blueberry'                 # Bluetooth configuration tool
                'pulseaudio-bluetooth'      # Bluetooth support for PulseAudio
            )
            for PKG in "${PKGS[@]}"; do
            pacman -S ${PKG} --noconfirm --needed
            done
        fi

        ### Wi-Fi

        if [ "${wifi}" == "y" ]; then
            PKGS=(
                # WIRELESS ---------------------------------------------------------------------------
                'dialog'                    # Enables shell scripts to trigger dialog boxex
                'wpa_supplicant'            # Key negotiation for WPA wireless networks
                'wireless_tools'            # wireless tools
            )
            for PKG in "${PKGS[@]}"; do
            pacman -S ${PKG} --noconfirm --needed
            done
        fi

        ### AUR Set-up
            
        # Add sudo no-password privileges
        sed -i 's|# %wheel ALL=(ALL) NOPASSWD: ALL|%wheel ALL=(ALL) NOPASSWD: ALL|' /etc/sudoers

        su ${user}

        # Install AUR Helper paru
        cd /tmp && git clone "https://aur.archlinux.org/paru.git" && cd paru
        makepkg -sric --noconfirm && cd

        PKGS=(
            # UTILITIES --------------------------------------------------------------------------
            'timeshift'                 # Backup programm
            'brave-bin'                 # Alternative chromium-based browser
            'vscodium-bin'              # Binary VS Code without MS branding/telemetry
            'scrcpy'                    # Android remot control tool
        )
        for PKG in "${PKGS[@]}"; do
        paru -S ${PKG} --noconfirm --needed
        done
CHROOT
}

function final {
    arch-chroot /mnt /bin/bash <<"CHROOT"

        # Enable Login Manager
        if [ "${de}" == "gnome" ]; then
            systemctl enable gdm
        fi

        if [ "${de}" == "kde" ]; then
            systemctl enable sddm
        fi

        # Enable Bluetooth Service
        if [ "${bluetooth}" == "yes" ]; then
            sed -i 's|#AutoEnable=false|AutoEnable=true|g' /etc/bluetooth/main.conf
            systemctl enable bluetooth
        fi

        # Enablie cups service daemon so we can print
        systemctl enable cups

        # Enable syncthing for user (never for root!)
        systemctl enable syncthing@${user}.service
        
        ### Set-up ZSH
        su ${user}
        # Fetch zsh config
        wget https://gitlab.com/Nelox/zsh/-/raw/master/.zshrc -O ~/.zshrc
        # Get Powerlevel0k Prompt
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
        # change shell to zsh
        sudo chsh -s /bin/zsh ${user}
        # Install awesome terminal font for p10k
        mkdir -p /usr/local/share/fonts && cd /usr/local/share/fonts && wget https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf
        
        # Clean orphans pkg
        if [[ ! -n $(sudo pacman -Qdt) ]]; then
            echo "No orphans to remove."
        else
            sudo pacman -Rns $(sudo pacman -Qdtq) --noconfirm
        fi

        # Remove sudo no-password privileges
        sudo sed -i 's|%wheel ALL=(ALL) NOPASSWD: ALL|# %wheel ALL=(ALL) NOPASSWD: ALL|g' /etc/sudoers
CHROOT
}

# call funtions
function main() { 
    preinstall
    baseInstall
    baseSetup
    softwareDesk
    final
}

main

umount -a
echo -e "\nThe installation has finished. You can now boot into your new system."
exit
