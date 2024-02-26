# astropi

Utility scripts to use a raspberry pi to control astrophotograephy gear.

## Create raspberry pi SD card

Using Raspberry Pi Imager, select Raspberry OS Lite 64bit bookworm.

Make sure to:

* Set hostname to what you call your rig.
* Configure your default wifi connection.
* Enable SSH server.

All these things can be done with the imager under the options tab.

## Update the system and install basic requirements

Update:
```
sudo apt update && sudo apt upgrade -y && sudo autoremove -y
```

Install requirements:
```
sudo apt install tmux git vim ripgrep htop
```

## Get installation script

Clone repository:

```
git clone git@github.com:jrhuerta/astropi.git
```

Run the installation script, answer a few questions and go make a cup of tea!
A few moments later... happy imaging!
