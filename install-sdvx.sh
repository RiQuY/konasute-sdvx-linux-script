#!/usr/bin/bash

function initialCheck {
    # Abort if the folder already exists.
    # The "mv" command in downloadKonasute() will fail otherwise.
    if [[ -d "${HOME}/Games/SOUND VOLTEX EXCEED GEAR" ]] ; then
        echo "Game already installed '${HOME}/Games/SOUND VOLTEX EXCEED GEAR' Aborting."
        exit
    fi
}

function intro() {
    echo "SOUND VOLTEX EXCEED GEAR Konasute installation script"
    echo "=============================================="
    echo "This script will do the following:"
    echo "- If not installed, install 'wine', 'winetricks', 'msitools', and 'curl' through your package manager;"
    echo "- Create a Wine prefix \"Konasute\" and install d3dcompiler_43, d3dcompiler_44, d3dcompiler_46, d3dcompiler47, dxvk, vcrun2010, cjkfonts; and set the audio driver for the prefix to ALSA;"
    echo "- Registers x86 and x64 versions of dsdmo.dll for the prefix for rendering sound effects in the game;"
    echo "- Create a registry entry on the Wine prefix that points the game it's installation path;"
    echo "- Downloads the Konasute installer from KONAMI through curl, extracts it using msitools' msiextract and places it under \"${HOME}/Games/SOUND VOLTEX EXCEED GEAR\". (assuming you are OK with KONAMI's terms of use);"
    echo "- Create a desktop file on \"${HOME}/.local/share/applications\" that configures the Konasute MIME protocol to launch the game;"
    echo "- Set up a Pipewire configuration file for low latency audio under \"${HOME}/.config/pipewire/pipewire.conf.d/\"."
    echo ""
    echo "Proceed? (N/y)"

    allow="n"
    read allow
    if [ ${allow,,} = "n" ] ; then
        echo "Aborting."
        exit
    fi
}

# Error output in english
export LANG=en_US.UTF-8
export LANGUAGE=en

user=$(whoami)
export WINEPREFIX=${HOME}/.local/share/wineprefixes/Konasute

function installTools() {
    packages=(wine winetricks msitools curl)

    echo "=============================================="
    echo "Installing tools through your package manager."
    echo "=============================================="

    if [[ -x "$(command -v dnf)" ]] ; then
        sudo dnf install -y ${packages[@]}
    elif [[ -x "$(command -v apt)" ]] ; then
        sudo apt install -y ${packages[@]}
    elif [[ -x "$(command -v zypper)" ]] ; then
        sudo zypper --non-interactive install ${packages[@]}
    elif [[ -x "$(command -v pacman)" ]] ; then
        sudo pacman -Sy ${packages[@]}
    else
        echo "Could not determine your package manager. Aborting."
        exit
    fi
}

function registerDMO() {
    cp ./x64/* $WINEPREFIX/drive_c/windows/syswow64/
    cp ./x86/* $WINEPREFIX/drive_c/windows/system32/
    wine regsvr32 dsdmo.dll
}

function setupWinePrefix() {
    echo "=============================================="
    echo "Setting up Wine prefix."
    echo "=============================================="
    winetricks d3dcompiler_42 d3dcompiler_43 d3dcompiler_46 d3dcompiler_47 dxvk vcrun2010 cjkfonts sound=alsa

    registerDMO

    cd ${HOME}
    echo "Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\\SOFTWARE\\KONAMI]

[HKEY_LOCAL_MACHINE\\SOFTWARE\\KONAMI\\SOUND VOLTEX EXCEED GEAR]
@=\"\"
\"InstallDir\"=\"Z:\\\\home\\\\${user}\\\\Games\\\\SOUND VOLTEX EXCEED GEAR\\\\\"
\"ResourceDir\"=\"Z:\\\\home\\\\${user}\\\\Games\\\\SOUND VOLTEX EXCEED GEAR\\\\Resource\\\\\"" > registry.reg # what a mess lmao
    wine regedit ./registry.reg
    rm ./registry.reg
}

function downloadKonasute() {
    echo "=============================================="
    echo "Downloading the SDVX installer."
    echo "=============================================="
    address="https://dks1q2aivwkd6.cloudfront.net/vi/installer/sdvx_installer_2022011800.msi"
    mkdir /tmp/konasute_sdvx
    cd /tmp/konasute_sdvx
    curl --output "sdvx_installer.msi" "$address"
    msiextract ./sdvx_installer.msi &> /dev/null

    # -p needed if "Games" folder doesn't exists
    mkdir -p "${HOME}/Games/SOUND VOLTEX EXCEED GEAR"
    mv "/tmp/konasute_sdvx/Games/SOUND VOLTEX EXCEED GEAR" "${HOME}/Games/"
    mkdir "${HOME}/Games/SOUND VOLTEX EXCEED GEAR/Resource"
    rm -rf /tmp/konasute_sdvx
}

function setupDesktopFile() {
    echo "=============================================="
    echo "Setting up desktop file association."
    echo "=============================================="

    cd ${HOME}
    echo "[Desktop Entry]
Type=Application
Name=SOUND VOLTEX EXCEED GEAR コナステ版 Launcher
Comment=Your thundering sound become the flash light that pierces soul of crowd, get the whole world into the voltex... Next generation music game.
Exec=env WINEPREFIX=/home/${user}/.local/share/wineprefixes/Konasute LANG=\"ja_JP\" PULSE_LATENCY_MSEC=10 wine \"/home/${user}/Games/SOUND VOLTEX EXCEED GEAR/launcher/modules/launcher.exe\" %u
MimeType=x-scheme-handler/konaste.sdvx
Categories=Game;
Icon=/home/${user}/Games/SOUND VOLTEX EXCEED GEAR/SOUND VOLTEX EXCEED GEAR.ico" > sdvx.desktop
    cp sdvx.desktop ${HOME}/Desktop
    mv ./sdvx.desktop ${HOME}/.local/share/applications
    sudo update-desktop-database
}

function setupPipewire() {
    echo "=============================================="
    echo "Setting up Pipewire configuration files."
    echo "=============================================="

    if [[ ! -d ${HOME}/.config/pipewire || ! -d ${HOME}/.config/pipewire/pipewire.conf.d/ ]] ; then
        mkdir -p ${HOME}/.config/pipewire/pipewire.conf.d/
    fi

    echo "context.properties = {
    default.clock.rate = 44100
    default.clock.min-quantum = 32
    default.clock.quantum = 128
}" > ${HOME}/.config/pipewire/pipewire.conf.d/lowlatency.conf

    devices=$(command pw-cli list-objects | awk '/node.name/ {name=$0} /media.class/ && /Audio\/Sink/ {gsub(/.*= "|"/,"",name); if (match(name, /konasuteloop/)==0){print name}}');

    targetDevice=${devices[0]};

    echo "context.modules = [
{
    name = libpipewire-module-loopback
    args = {
        audio.position = [ FL FR ]
        capture.props = {
            media.class = Audio/Sink
            audio.format = S16LE
            audio.rate = 44100
            audio.channels = 2
            node.name = konasuteloop
            node.description = \"Konasute 44100Hz loopback sink\"
        }
        playback.props = {
            node.passive = true
            node.name = konasuteloop.output
            node.description = \"Konasute 44100Hz loopback output\"
            target.object = \"${targetDevice}\"
            audio.format = S16LE
        }
    }
    }
]" > ${HOME}/.config/pipewire/pipewire.conf.d/loopback.conf


    if [[ -d /run/systemd/system ]] ; then
        systemctl --user restart pipewire pipewire-pulse wireplumber
        echo "Restarted pipewire."
    else
        echo "It seems your system does not use systemd to be managed. Please restart the pipewire service and pipewire-pulse socket through your system control manager under user mode."
    fi
}

function outro() {
    echo "=============================================="
    echo "Installation complete."
    echo "=============================================="
    echo "Be sure to configure SDVX's audio options (オーディオ設定) to use WASAPI Exclusive mode (WASAPI (排他モード)), the buffering mode to timer (タイマー駆動). A suggested initial latency setting/buffer size is of 10ms."
    echo "Depending on your controller, you might have to set up a remap string. Refer to the github page for more details."
    echo "Remember to change your audio device profile to Pro Audio mode."
    echo "If the game is not starting after logging in through the website, reboot your browser/PC".
    echo "=============================================="
}

initialCheck
intro
installTools
setupWinePrefix
downloadKonasute
setupDesktopFile
setupPipewire
outro
