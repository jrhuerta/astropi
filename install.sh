#!/usr/bin/env bash

SYSTEM_NAME=$(hostnamectl hostname)

HOTSPOT_NAME=${HOTSPOT_NAME:-$SYSTEM_NAME}
HOTSPOT_PASSWORD=${HOTSPOT_PASSWORD:-"password"}

SOURCE_FOLDER=${SOURCE_FOLDER:-$HOME/src}
BUILD_FOLDER=${BUILD_FOLDER:-$HOME/build}
INSTALL_FOLDER=${INSTALL_FOLDER:-/usr}

INDI_RELEASE=${INDI_RELEASE:-"v2.0.6"}
LIBXISF_RELEASE=${LIBXISF_RELEASE:-"v0.2.9"}
PHD2_RELEASE=${PHD2_RELEASE:-"v2.6.13"}

VNC_RESOLUTION="1920x1080"

#COLOR:
#How to use: echo $(color red "Some error in red")
function color {
    local color=${1}
    shift
    local text="${@}"
    
    case ${color} in
        red    ) tput setaf 1 ;;
        green  ) tput setaf 2 ;;
        yellow ) tput setaf 3 ;;
        blue   ) tput setaf 4 ;;
        pink   ) tput setaf 5 ;;
        cyan   ) tput setaf 6 ;;
        grey   ) tput setaf 7 ;;
    esac
    
    echo -en "${text}"
    tput sgr0
}

function configure_conectivity {
    echo $(color green "Configuring connectivity")

    # Determine default wifi connection
    DEFAULT_WIFI_CONNECTION=$(nmcli -t -f UUID,DEVICE connection show --active | grep wlan0 | cut -f1 -d:)
    
    # Update default wifi connection to set priority and add autoconnect and retries
    sudo nmcli connection modify $DEFAULT_WIFI_CONNECTION \
        connection.autoconnect yes \
        connection.autoconnect-priority 10 \
        connection.autoconnect-retries 3 \
    && echo $(color green "[$DEFAULT_WIFI_CONNECTION] wifi connection updated.")
    
    # Delete any connection with the same name as the hotspot
    for connection in $(nmcli -t -f NAME,UUID connection show | grep $HOTSPOT_NAME | cut -d: -f2); do
        sudo nmcli connection delete $connection
        echo $(color yellow "[$connection] connection deleted.")
    done

    # Add default fallback hotspot connection
    sudo nmcli connection add \
        type wifi \
        ifname wlan0 \
        con-name $HOTSPOT_NAME \
        autoconnect yes \
        connection.autoconnect-priority 0 \
        ssid $HOTSPOT_NAME \
        802-11-wireless.mode ap \
        ipv4.method shared \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$HOTSPOT_PASSWORD" \
    && echo $(color green "Hotspot connection added. SSID: $HOTSPOT_NAME Password: $HOTSPOT_PASSWORD")

    # Enable network manager for ethernet
    if [ -n "$(grep 'managed=false' /etc/NetworkManager/NetworkManager.conf)" ]
    then
        sudo sed -i "s/managed=false/managed=true/g" /etc/NetworkManager/NetworkManager.conf
    fi

    # Enable dhcp for ethernet
    ETH0_CONNECTION=$(nmcli -t -f UUID,TYPE connection show | grep ethernet | cut -f1 -d:)
    if [ -n "$ETH0_CONNECTION" ]; then
        sudo nmcli connection modify $ETH0_CONNECTION \
            ipv4.method shared \
        && echo $(color green "[$ETH0_CONNECTION] dhcp enabled.")
    fi

    # enable dnsmasq for network manager
    sudo bash -c 'cat > /etc/NetworkManager/conf.d/10-dnsmasq.conf' << EOF
[main]
dns=dnsmasq
EOF
    sudo systemctl restart NetworkManager
    sudo systemctl status NetworkManager | cat
}

function configure_swap {
    # Increase swap size to 2GB
    sudo apt install -y zram-tools
    sudo bash -c 'cat > /etc/default/zramswap' << EOF
ALGO=lz4
PERCENT=50
EOF
    sudo zramswap restart
    sudo dphys-swapfile swapoff
    sudo sed -i 's/CONF_SWAPSIZE=[0-9]\+/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile
    sudo dphys-swapfile setup
    sudo dphys-swapfile swapon
}

function install_vnc {
    sudo apt install -y xserver-xorg xinit x11-utils x11-session-utils fluxbox xterm tightvncserver
    vncpasswd
    sudo bash -c 'cat > /etc/systemd/system/vncserver@.service' << EOF
[Unit]
Description=Start TightVNC server at startup
After=syslog.target network.target

[Service]
Type=forking
User=${USER}
Group=${USER}
WorkingDirectory=/home/${USER}

PIDFile=/home/${USER}/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -depth 24 -geometry ${VNC_RESOLUTION} :%i
ExecStop=/usr/bin/vncserver -kill :%i

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable vncserver@1.service
    sudo systemctl start vncserver@1
    sudo systemctl status vncserver@1 | cat
}

function _clone_and_build() {
    local REPO=$1
    local RELEASE=$2
    local SOURCE=$3
    local BUILD=$4
    shift 4
    
    if [ -d $SOURCE ]; then
        rm -rf $SOURCE
    fi
    if [ -d $BUILD ]; then
        sudo rm -rf $BUILD
    fi
    mkdir -p $BUILD
    git clone -c advice.detachedHead=false --branch $RELEASE --depth 1 $REPO $SOURCE \
        && cd $BUILD \
        && cmake "$@" $SOURCE \
        && make -j4 \
        && sudo make install
}

function build_libxisf() {
    sudo apt -y install cmake build-essential libzstd1
    _clone_and_build https://gitea.nouspiro.space/nou/libXISF.git $LIBXISF_RELEASE $SOURCE_FOLDER/libXISF $BUILD_FOLDER/libXISF 
}

function build_indi_core() {
    sudo apt install -y \
        git \
        cdbs \
        dkms \
        cmake \
        fxload \
        libev-dev \
        libgps-dev \
        libgsl-dev \
        libraw-dev \
        libusb-dev \
        zlib1g-dev \
        libftdi-dev \
        libjpeg-dev \
        libkrb5-dev \
        libnova-dev \
        libtiff-dev \
        libfftw3-dev \
        librtlsdr-dev \
        libcfitsio-dev \
        libgphoto2-dev \
        build-essential \
        libusb-1.0-0-dev \
        libdc1394-dev \
        libboost-regex-dev \
        libcurl4-gnutls-dev \
        libtheora-dev

    _clone_and_build https://github.com/indilib/indi.git $INDI_RELEASE $SOURCE_FOLDER/indi-core $BUILD_FOLDER/indi-core -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Debug
}

function build_indi_3rdparty() {
    sudo apt -y install \
        libnova-dev \
        libcfitsio-dev \
        libusb-1.0-0-dev \
        zlib1g-dev \
        libgsl-dev \
        build-essential \
        cmake \
        git \
        libjpeg-dev \
        libcurl4-gnutls-dev \
        libtiff-dev \
        libfftw3-dev \
        libftdi-dev \
        libgps-dev \
        libraw-dev \
        libdc1394-dev \
        libgphoto2-dev \
        libboost-dev \
        libboost-regex-dev \
        librtlsdr-dev \
        liblimesuite-dev \
        libftdi1-dev \
        libavcodec-dev \
        libavdevice-dev

    local REPO=https://github.com/indilib/indi-3rdparty.git
    local RELEASE=$INDI_RELEASE
    local SOURCE=$SOURCE_FOLDER/indi-3rdparty
    local BUILD=$BUILD_FOLDER

    if [ -d $SOURCE ]; then
        rm -rf $SOURCE
    fi
    git clone -c advice.detachedHead=false --branch $RELEASE --depth 1 $REPO $SOURCE
    COMPONENTS=("libasi" "libatik" "libsvbony" "indi-svbony" "indi-asi" "indi-atik" "indi-eqmod" "indi-gphoto")
    for COMPONENT in "${COMPONENTS[@]}"; do
        echo $(color green "Building $COMPONENT")
        SOURCE=$SOURCE_FOLDER/indi-3rdparty/$COMPONENT
        BUILD=$BUILD_FOLDER/$COMPONENT
        echo "SOURCE: $SOURCE"
        echo "BUILD: $BUILD"

        if [ -d $BUILD ]; then
           sudo rm -rf $BUILD
        fi
        mkdir -p $BUILD
        cd $BUILD \
            && cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Debug $SOURCE \
            && make -j4 \
            && sudo make install
    done
}

function build_phd2() {
    sudo apt install -y \
        build-essential \
        git \
        cmake \
	gettext \
	pkg-config \
        libindi-dev \
        libnova-dev \
        libcurl4-gnutls-dev \
        wx-common \
        wx3.2-i18n \
        zlib1g-dev \
        libx11-dev \
        libcurl4-gnutls-dev \
	libwxgtk3.2-dev
    _clone_and_build https://github.com/OpenPHDGuiding/phd2.git $PHD2_RELEASE $SOURCE_FOLDER/phd2 $BUILD_FOLDER/phd2 
}

function install_GSC() {
    echo $(color green "Building and Installing GSC")
    if [ ! -d /usr/share/GSC ]
    then
        if [ ! -f $HOME/gsc/bincats_GSC_1.2.tar.gz ]
        then
            mkdir -p $HOME/gsc
            wget -O $HOME/gsc/bincats_GSC_1.2.tar.gz http://cdsarc.u-strasbg.fr/viz-bin/nph-Cat/tar.gz?bincats/GSC_1.2
        fi
        cd $HOME/gsc \
            && tar -xvzf bincats_GSC_1.2.tar.gz \
            && cd src \
            && make -j $(expr $(nproc) + 2) \
            && sudo mv gsc.exe /usr/bin/gsc \
	    && cd .. \
	    && rm -rf bin-dos src bincats_GSC_1.2.tar.gz bin/decode.exe bin/gsc.exe \
	    && sudo mv $HOME/gsc /usr/share/GSC
else
	echo "GSC is already installed"
fi
}

function install_indiweb() {
    sudo apt install -y python3-venv python3-dev
    if [ -d $HOME/indiweb ]; then
        rm -rf $HOME/indiweb
    fi
    python3 -m venv $HOME/indiweb
    $HOME/indiweb/bin/pip install -U git+https://github.com/knro/indiwebmanager.git@master importlib-metadata 
    sudo bash -c 'cat > /etc/systemd/system/indiweb.service' << EOF
[Unit]
Description=INDI Web Manager
After=multi-user.target

[Service]
Type=idle
User=${USER}
Environment="GSCDAT=/usr/share/GSC"
ExecStart=$HOME/indiweb/bin/indi-web -v
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable indiweb
    sudo systemctl start indiweb
    sudo systemctl status indiweb | cat
}

case $1 in
    connectivity)
        configure_conectivity
    ;;
    swap)
        configure_swap
    ;;
    vnc)
        install_vnc 
    ;;
    libxisf)
        build_libxisf
    ;;
    indi-core)
        build_indi_core
    ;;
    indi-3rdparty)
        build_indi_3rdparty
    ;;
    phd2)
        build_phd2
    ;;
    indiweb)
        install_indiweb
    ;;
    gsc)
        install_GSC
    ;;
    all)
	configure_conectivity \
		&& configure_swap \
		&& build_libxisf \
		&& build_indi_core \
		&& build_indi_3rdparty \
		&& build_phd2 \
		&& install_indiweb \
		&& install_gsc
    ;;
    *)
        echo "Usage: $0 {hostname|connectivity|swap|vnc|libxisf|indi-core|indi-3rdparty|phd2|indiweb|gsc}"
        exit 1
    ;;
esac
