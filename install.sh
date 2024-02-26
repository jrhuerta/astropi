#!/usr/bin/env bash

SYSTEM_NAME=$(hostnamectl hostname)

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


function hostname() {
    # Query the user for the system name with a default value
    read -p "Enter the system name [$SYSTEM_NAME]: " INPUT

    # Set the system name to the user input or the default value
    SYSTEM_NAME=${INPUT:-$SYSTEM_NAME}

    #if system_name is different than the current hostname change it
    if [ $SYSTEM_NAME != $(hostnamectl hostname) ]; then
        # set hostname to the system name
        sudo hostnamectl hostname $SYSTEM_NAME
        echo $(color green "Hostname changed to $SYSTEM_NAME")
    fi
}


function configure_conectivity {
    # Determine default wifi connection
    $DEFAULT_WIFI_CONNECTION=$(nmcli -t -f UUID,DEVICE connection show --active | grep wlan0 | cut -f1 -d:)

    read -p "Enter hotspot name [$SYSTEM_NAME]: " HOTSPOST_NAME
    read -p "Enter hotspot password [$SYSTEM_NAME]: " HOTSPOST_PASSWORD

    HOTSPOST_NAME=${HOTSPOST_NAME:-$SYSTEM_NAME}
    HOTSPOST_PASSWORD=${HOTSPOST_PASSWORD:-$SYSTEM_NAME}

    # Update default wifi connection to set priority and add autoconnect and retries
    sudo nmcli connection modify $DEFAULT_WIFI_CONNECTION \
        connection.autoconnect yes \
        connection.autoconnect-priority 10 \
        connection.autoconnect-retries 3 \
    && echo $(color green "Default wifi connection updated.")
    
    # Add default fallback hotspot connection
    sudo nmcli con add \
        type wifi \
        ifname wlan0 \
        con-name testing \
        autoconnect yes \
        connection.autoconnect-priority 0 \
        ssid testing \
        802-11-wireless.mode ap \
        802-11-wireless.band bg \
        ipv4.method shared \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "testing" \
    && echo $(color green "Hotspot connection added.")
}

case $1 in
    hostname)
        hostname
        ;;
    connectivity)
        configure_conectivity
        ;;
    *)
        echo "Usage: $0 {hostname|connectivity}"
        exit 1
        ;;
esac