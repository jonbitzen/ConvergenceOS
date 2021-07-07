#!/bin/bash
#
# Copyright (C) 2018  Jonathan Railsback
#
# This file is part of ConvergenceOS.
#
# ConvergenceOS is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation
#
# ConvergenceOS is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ConvergenceOS.  If not, see <https://www.gnu.org/licenses/>.


OLD_DESKTOP_USER=desktop
NEW_DESKTOP_USER=$(logname)
STEAM_USER=steam
LSB_RELEASE_ID=NONE
LIGHTDM_BIN="/usr/sbin/lightdm"

function create_steam_user {

adduser --disabled-password --gecos "" ${STEAM_USER}

usermod -a -G steam,nopasswdlogin ${STEAM_USER}

}

function change_steamos_session_desktop_user {

    local OLD_DESKTOP_SESSION=gnome
    local NEW_DESKTOP_SESSION=${DESKTOP_SESSION}

    sed -i 's/'"${OLD_DESKTOP_USER}"'/'"${NEW_DESKTOP_USER}"'/g' /usr/bin/steamos-session
    sed -i 's/'"${OLD_DESKTOP_SESSION}"'/'"${NEW_DESKTOP_SESSION}"'/g' /usr/bin/steamos-session

    usermod -a -G nopasswdlogin ${NEW_DESKTOP_USER}

}

function modify_desktop_account_service_settings {

DESKTOP_USER_ACCOUNT_SETTINGS="
[User]
XSession=${DESKTOP_SESSION}
SystemAccount=false
"

rm -f /var/lib/AccountsService/users/$NEW_DESKTOP_USER

printf '%s' "$DESKTOP_USER_ACCOUNT_SETTINGS" >> /var/lib/AccountsService/users/$NEW_DESKTOP_USER

}

function modify_steam_account_service_settings {

STEAM_ACCOUNT_SETTINGS="
[User]
XSession=steamos
SystemAccount=false
"

rm -f /var/lib/AccountsService/users/${STEAM_USER}

printf '%s' "$STEAM_ACCOUNT_SETTINGS" >> /var/lib/AccountsService/users/${STEAM_USER}

}

function create_steamos_repo_prefs {

STEAMOS_REPO_PREF_DATA="
Package: *
Pin: origin repo.steampowered.com
Pin-Priority: -1

Package: steam steamos-compositor steamos-modeswitch-inhibitor valve-archive-keyring
Pin: origin repo.steampowered.com
Pin-Priority: 500
"

printf '%s' "$STEAMOS_REPO_PREF_DATA" >> /etc/apt/preferences

}

function setup_lightdm_conf {

LIGHTDM_CONF="
[Seat:*]
autologin-guest=false
# autologin-user=${STEAM_USER}
# autologin-user-timeout=0
user-session=steamos-session
pam-service=lightdm-autologin
allow-guest=false
"

rm -f /etc/lightdm/lightdm.conf

printf '%s' "$LIGHTDM_CONF" >> /etc/lightdm/lightdm.conf

}

function add_management_scripts {

    cp returntosteam.sh /usr/bin
    cp start-steam-client.sh /usr/bin

    cp return-to-steamos.desktop /home/${NEW_DESKTOP_USER}/Desktop
    chown ${NEW_DESKTOP_USER}.${NEW_DESKTOP_USER} /home/${NEW_DESKTOP_USER}/Desktop/return-to-steamos.desktop
    chmod u+x /home/${NEW_DESKTOP_USER}/Desktop/return-to-steamos.desktop
    
    cp start-steam-client.desktop /home/${NEW_DESKTOP_USER}/Desktop
    chown ${NEW_DESKTOP_USER}.${NEW_DESKTOP_USER} /home/${NEW_DESKTOP_USER}/Desktop/start-steam-client.desktop
    chmod u+x /home/${NEW_DESKTOP_USER}/Desktop/start-steam-client.desktop

    # TODO: see if gsettings will work as well
    if [ "${LSB_RELEASE_ID}" == "Ubuntu" ]; then
        su -c "gio set /home/${NEW_DESKTOP_USER}/Desktop/return-to-steamos.desktop \"metadata::trusted\" yes" ${NEW_DESKTOP_USER}
        su -c "gio set /home/${NEW_DESKTOP_USER}/Desktop/start-steam-client.desktop \"metadata::trusted\" yes" ${NEW_DESKTOP_USER}
    fi

}

function create_steamos_repo_list {

STEAMOS_REPO_LIST_DATA="
deb [trusted=yes] http://repo.steampowered.com/steamos brewmaster main contrib non-free
deb-src [trusted=yes] http://repo.steampowered.com/steamos brewmaster main contrib non-free
"

printf '%s' "$STEAMOS_REPO_LIST_DATA" >> /etc/apt/sources.list.d/steamos.list

}

function create_untrusted_steamos_repo_list {

STEAMOS_REPO_LIST_DATA="
deb http://repo.steampowered.com/steamos brewmaster main contrib non-free
deb-src http://repo.steampowered.com/steamos brewmaster main contrib non-free
"

rm -rf /etc/apt/sources.list.d/steamos.list

printf '%s' "$STEAMOS_REPO_LIST_DATA" >> /etc/apt/sources.list.d/steamos.list

}

function install_steamos_tools {

    apt-get -y install git
    su -c "cd ~; git clone https://github.com/mdeguzis/SteamOS-Tools.git; exit" $NEW_DESKTOP_USER
    
}

function add_repositories {

    create_steamos_repo_list
    create_steamos_repo_prefs

    apt-get update
    apt-get -y --allow-unauthenticated install valve-archive-keyring
    apt-get update

    create_untrusted_steamos_repo_list
    apt-get update

}


function install_openpht {

    wget https://github.com/RasPlex/OpenPHT/releases/download/v1.8.0.148-573b6d73/openpht_1.8.0.148-573b6d73-xenial_amd64.deb
    gdebi -n openpht_1.8.0.148-573b6d73-xenial_amd64.deb
    rm openpht_1.8.0.148-573b6d73-xenial_amd64.deb
    
    # needed for OpenPHT, possibly other things too
    apt-get -y install libcurl3

}

function install_plex_media_server {

    # Plex Media Server
    wget -q https://downloads.plex.tv/plex-keys/PlexSign.key -O - | apt-key add -
    
PLEX_MEDIA_SERVER_REPO="
# When enabling this repo please remember to add the PlexPublic.Key into the apt setup.
# wget -q https://downloads.plex.tv/plex-keys/PlexSign.key -O - | sudo apt-key add -
deb https://downloads.plex.tv/repo/deb/ public main
"

printf '%s' "$PLEX_MEDIA_SERVER_REPO" >> /etc/apt/sources.list.d/plexmediaserver.list

apt-get update

apt-get -y install plexmediaserver <<PACKAGE_INSTALL_ANSWERS
N
PACKAGE_INSTALL_ANSWERS

usermod -a -G $NEW_DESKTOP_USER plex
usermod -a -G plex $NEW_DESKTOP_USER

}

function install_scm_server_packages {


    apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 D742B261

SCM_SERVER_REPO="
deb http://maven.scm-manager.org/nexus/content/repositories/releases ./
"

printf '%s' "$SCM_SERVER_REPO" >> /etc/apt/sources.list.d/scmserver.list

apt-get update

apt-get -y --allow-unauthenticated install scm-server

}

function install_google_chrome {

    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    gdebi -n google-chrome-stable_current_amd64.deb
    rm google-chrome-stable_current_amd64.deb

}

function install_steamos_packages {
    dpkg -i multiarch-support_2.27-3ubuntu1_amd64.deb
    apt-get -y install steamos-compositor steamos-modeswitch-inhibitor steam
    sed -i 's/'"-steamos"'/'""'/g' /usr/bin/steamos-session
}

function check_lightdm_install {

    local CURRENT_DM_BIN=$(cat /etc/X11/default-display-manager)

    if [ "$CURRENT_DM_BIN" != "${LIGHTDM_BIN}" ]; then
        zenity --info --width 300 --text "Detected that lightdm is not the current display manager.\n\nPlease select lightdm at the prompt and press Enter" --title "Install lightdm"
        dpkg-reconfigure lightdm
    else
        return
    fi

	CURRENT_DM_BIN=$(cat /etc/X11/default-display-manager)

    if [ "$CURRENT_DM_BIN" != "${LIGHTDM_BIN}" ]; then
        
        while : ; do

            zenity --question --width 300 --text "Detected that lightdm is not the current display manager.  Note that ConvergenceOS will not work properly without lightdm.\n\nDo you want to try again?" --title "Install lightdm"

            if [ "$?" == "1" ]; then
                break
            fi

            dpkg-reconfigure lightdm
            CURRENT_DM_BIN=$(cat /etc/X11/default-display-manager)

            if [ "$CURRENT_DM_BIN" == "${LIGHTDM_BIN}" ]; then
                break
            fi
            
        done         
        
    fi

}

function install_base_packages {

    apt-get -y upgrade
    apt-get -y install gdebi

    LIGHTDM_PKG_FOUND=$(dpkg-query -W lightdm | awk '{print $1}')
    if [ "$LIGHTDM_PKG_FOUND" != "lightdm" ]; then
        zenity --info --width 300 --text "ConvergenceOS installer will now install lightdm display manager.\n\nWhen prompted, please select lightdm and press Enter" --title "Install lightdm"
        apt-get -y install lightdm
    fi

    check_lightdm_install

    apt-get -y install ssh
    apt-get -y install samba
    apt-get -y install pavucontrol
    apt-get -y install vim
    apt-get -y install python-is-python3

    if [ "$LSB_RELEASE_ID" == "LinuxMint" ]; then
        apt-get -y install light-themes
    fi

    if [ "$LSB_RELEASE_ID" == "Ubuntu" ]; then
        apt-get -y install synaptic
        apt-get -y install mesa-utils
    fi

}

function purge_desktop_apps {

    apt-get remove -y --purge "^libreoffice.*"
    apt-get remove -y --purge "^gimp.*"
    apt-get remove -y --purge "^pix.*"
    apt-get remove -y --purge "^rhythmbox.*"
    apt-get remove -y --purge "^simple-scan.*"
    apt-get remove -y --purge "^thunderbird.*"
    apt-get remove -y --purge "^pidgin.*"
    apt-get remove -y --purge "^hexchat.*"
    
    apt-get autoremove -y --purge

}

function fix_controller_udev_rules {

    cp 60-steam-input.rules /lib/udev/rules.d

}

function setup_samba {

    cp smb.conf /etc/samba
    usermod -a -G sambashare ${NEW_DESKTOP_USER}
    smbpasswd -a ${NEW_DESKTOP_USER}

}

function open_driver_install_app {

    DRIVER_VENDOR_STRING=$(glxinfo | grep "vendor" | grep -v grep)
    DRIVER_VENDOR_ID=$(python get_driver_id.py "${DRIVER_VENDOR_STRING}")
    
    if [ "$DRIVER_VENDOR_ID" == "MESA" ]; then
        DRIVER_INSTALL_TEXT="ConvergenceOS has detected that your primary graphics adapter is using the Mesa driver.\n\nConvergenceOS will also install the Mesa VDPAU and Vulkan drivers from the default system repository"
        zenity --info --width 300 --text "${DRIVER_INSTALL_TEXT}" --title "Mesa Drivers"
        apt-get -y install mesa-vdpau-drivers
        apt-get -y install mesa-vulkan-drivers
        return

    elif [ "$DRIVER_VENDOR_ID" == "NOUVEAU" ]; then

        DRIVER_INSTALL_TEXT="ConvergenceOS has detected that your primary graphics adapter is using the Open Source Nouveau driver for nVidia graphics cards.  Using proprietary drivers is recommended for Nvidia graphics adapters.\n\nWould you like to install proprietary graphics drivers for your device?\n\nThe installer may request your administrator password during this process."

        zenity --question --width 300 --text "${DRIVER_INSTALL_TEXT}" --title "Install Nvidia Graphics Drivers"

        INSTALL_DRIVERS="$?"

        if [ "$INSTALL_DRIVERS" == "1" ]; then
            return
        fi

        # install the nvidia graphics drivers PPA, and update the repository
        add-apt-repository -y ppa:graphics-drivers/ppa
        apt-get update
        sleep 1

        if [ "$LSB_RELEASE_ID" == "Ubuntu" ]; then
            software-properties-gtk --open-tab=4
        elif [ "$LSB_RELEASE_ID" == "LinuxMint" ]; then

            driver-manager	
            sleep 5
            MINT_DRIVER_PID=$(pgrep mintdriver)

            while [ "$MINT_DRIVER_PID" != "" ]; do
                sleep 1
                MINT_DRIVER_PID=$(pgrep mintdriver)
            done

        fi

    elif [ "$DRIVER_VENDOR_ID" == "NVIDIA" ]; then
    
        DRIVER_INSTALL_TEXT="ConvergenceOS has detected that your primary graphics adapter is using the propietary Nvidia graphics driver.\n\nNo additional action is needed.\n\nIf you would like to change this later please use the package manager and driver installer that comes with your Linux distribution."
        zenity --info --width 300 --text "${DRIVER_INSTALL_TEXT}" --title "Proprietary Nvidia Drivers"
        return

    else

        DRIVER_INSTALL_TEXT="ConvergenceOS couldn't identify the graphics drivers currently installed in your system.\n\nPlease consult your system hardware manager, package manager, and driver installer to install graphics drivers if needed."
        zenity --info --width 300 --text "${DRIVER_INSTALL_TEXT}" --title "Unknown Graphics Drivers"
        return

    fi

}

function setup_steam_client {


    STEAM_INSTALL_TEXT="ConvergenceOS will now install the Steam Desktop Client.  After installation is complete, please login to your Steam account.\n\nOnce your login is successful, please exit the Steam client so that driver detection and installation may continue.\n\nNote that you may need to right-click on Steam icon in the Dock or Task Bar on your desktop and select Quit to fully exit the Steam Desktop Client."
    
    zenity --info --width 300 --text "${STEAM_INSTALL_TEXT}" --title "Steam Installation"

    steam

    # xhost +
    # su -c "steam" steam
}

function install_optional_apps {

    install_google_chrome

    install_steamos_tools

    purge_desktop_apps

    #install_openpht

    install_plex_media_server

    install_scm_server_packages

    setup_samba

}

function convergence_install_finished {

    zenity --question --width 300 --text "ConvergenceOS installation and setup complete.\n\nWould you like to reboot your computer now?"  --ok-label="Reboot Now" --cancel-label="Reboot Later Manually"

    REBOOT_NOW=$?

    if [ "$REBOOT_NOW" == "0" ]; then
        reboot
    fi

}

function setup_convergence_os {

    check_dist

    add_repositories

    install_base_packages

    install_steamos_packages

    fix_controller_udev_rules

    # create_steam_user

    # change_steamos_session_desktop_user

    # add_management_scripts

    # modify_desktop_account_service_settings

    # modify_steam_account_service_settings

    setup_lightdm_conf

    setup_steam_client

    open_driver_install_app

    convergence_install_finished

}

function check_dist {

    LSB_RELEASE_ID=$(lsb_release --short --id)
    LSB_RELEASE_NUMBER=$(lsb_release --short --release)
    # TODO: can we use some sort of regex or glob pattern to match 19.X or 18.04.X?  
    if [ "$LSB_RELEASE_ID" == "LinuxMint" ]; then
        if [ "$LSB_RELEASE_NUMBER" != "19" ]; then       
            echo "Unsupported LinuxMint version ${LSB_RELEASE_NUMBER}"
        fi

    elif [ "$LSB_RELEASE_ID" == "Ubuntu" ]; then
        if [ "$LSB_RELEASE_NUMBER" != "18.04" ] && [ "$LSB_RELEASE_NUMBER" != "18.04.1" ]; then          
            echo "Unsupported Ubuntu version ${LSB_RELEASE_NUMBER}"
        fi
    else
        echo "Unsupported distribution $LSB_RELEASE_ID $LSB_RELEASE_NUMBER"
    fi



}

function welcome_to_convergence_os {

zenity --info --width 600 --text "This program will install ConvergenceOS on your PC.  ConvergenceOS installs the basic SteamOS(R) video game console-like interface on top of a robust Ubuntu-based Linux operating system, suitable for home server applications.\n\nBy entering the Ubuntu desktop from your SteamOS(R) interface, you can administer your system, add server programs, configure your Steam(R) client, and update your display drivers.\n\nThis program should initially be launched as the unprivileged desktop user, to obtain desktop environment information.  Your administrator password may be requested later when elevated privileges are needed to proceed with the installation, unless you have previously run administrator commands from this terminal."

}

if [ "$1" != "SKIP_INTRO" ]; then
	welcome_to_convergence_os
fi

if [[ $EUID -eq 0 ]]; then

	DESKTOP_SESSION=$2
	if [ "$DESKTOP_SESSION" == "" ]; then
		zenity --info --width 300 --text "Couldn't find desktop session environment info.  Please be sure to run this program as the default desktop user (without invoking administrator privileges).\n\nThe installer may ask you to enter your administrator password later, unless you have previously run administrator commands from this terminal."
		exit
	fi
    BUILD_CONVERGENCE_HOME=$(dirname $(realpath $0))
	setup_convergence_os
else	
	# BUILD_CONVERGENCE_HOME=$(dirname $(realpath $0))
    
    SUDO_PASSWORD=$(zenity --password --title "Install ConvergenceOS")

    echo ${SUDO_PASSWORD} | sudo -S ls
    PASSWORD_OK=$?

    if [ "$PASSWORD_OK" != "0" ]; then
        zenity --info --width 100 --text "Incorrect password"
        exit
    fi

    echo ${SUDO_PASSWORD} | sudo -S $0 "SKIP_INTRO" $DESKTOP_SESSION

fi


