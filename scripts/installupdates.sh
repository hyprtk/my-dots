#!/bin/bash
# ... (Header remains the same) ...

sleep 1
source ~/my-dots/scripts/library.sh
clear

# ------------------------------------------------------
# Check Filesystem Type
# ------------------------------------------------------
ROOT_FS_TYPE=$(findmnt -no FSTYPE /)
echo "Detected Root Filesystem: $ROOT_FS_TYPE"

# ------------------------------------------------------
# Confirm Start
# ------------------------------------------------------
while true; do
    read -p "DO YOU WANT TO START THE UPDATE NOW? (Yy/Nn): " yn
    case $yn in
        [Yy]* )
            echo ""
        break;;
        [Nn]* ) 
            exit;
        break;;
        * ) echo "Please answer yes or no.";;
    esac
done

# ------------------------------------------------------
# Snapshot Logic
# ------------------------------------------------------

if [[ "$ROOT_FS_TYPE" == "btrfs" ]]; then
    # BTRFS Logic: Check for Snapper
    if ! command -v snapper &> /dev/null; then
        echo "Btrfs detected but Snapper is not installed."
        while true; do
            read -p "DO YOU WANT TO INSTALL AND CONFIGURE SNAPPER NOW? (Yy/Nn): " sn
            case $sn in
                [Yy]* )
                    # Assuming snapper-setup.sh is in the same directory
                    sudo bash ~/my-dots/scripts/snapper-setup.sh
                break;;
                [Nn]* ) 
                    echo "Skipping Snapper setup. Proceeding with update without automated snapshots."
                break;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    else
        echo "Snapper detected. snap-pac will handle snapshots automatically during update."
    fi
else
    # Non-BTRFS Logic: Timeshift
    if [[ $(_isInstalledYay "Timeshift") == 1 ]]; then
        while true; do
            read -p "DO YOU WANT TO CREATE A TIMESHIFT SNAPSHOT? (Yy/Nn): " yn
            case $yn in
                [Yy]* )
                    echo ""
                    read -p "Enter a comment for the snapshot: " c
                    sudo timeshift --create --comments "$c"
                    sudo timeshift --list
                    sudo ~/archcraft-dots/sddm/update-TS-run.sh
                    echo "DONE. Snapshot $c created!"
                    echo ""
                break;;
                [Nn]* ) 
                break;;
                * ) echo "Please answer yes or no.";;
            esac
        done
    fi
fi

echo "-----------------------------------------------------"
echo "Start update"
echo "-----------------------------------------------------"
echo ""

# snap-pac (installed via snapper-setup.sh) hooks into pacman/yay automatically
yay

notify-send "Update complete"