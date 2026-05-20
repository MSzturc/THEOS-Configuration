#!/bin/bash

# Funktion zum Warten auf den MCU-Neustart
wait_for_mcu_reboot() {
    local board=$1
    local timeout=${2:-10}
    local elapsed=0

    echo "Waiting for MCU Reboot..."
    while [ ! -h "/dev/$board" ] && [ $elapsed -lt $timeout ]; do
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [ -h "/dev/$board" ]; then
        echo "MCU reboot successful."
        return 0
    else
        echo "Error: MCU did not reboot within $timeout seconds."
        return 1
    fi
}

# Argument-Parsing: --auto skippt den DFU-Fallback und exitet bei
# gescheitertem Serial-Flash mit Code 1.
auto_mode=0
for arg in "$@"; do
    case "$arg" in
        --auto) auto_mode=1 ;;
        *) ;;
    esac
done

# Sicherstellen, dass das Skript als root ausgeführt wird.
# THEOS_BYPASS_ROOT_CHECK existiert ausschließlich für die Unit-Tests,
# die das Skript ohne echte root-Privilegien stubben.
if [ "$EUID" -ne 0 ] && [ -z "${THEOS_BYPASS_ROOT_CHECK:-}" ]; then
    echo "ERROR: Please run as root"
    exit 1
fi

# Aktuelles Verzeichnis des Skripts ermitteln
current_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Helper zur rekursiven [mcu]-Suche und zur user_dir-Auflösung
source "$current_dir/helpers/parse_mcu.sh"
source "$current_dir/utils.sh"

# Pfad zur printer.cfg. user_dir() löst auf den Drucker-User auf (pi auf
# der Pi), nicht auf $HOME — bei einem `sudo flash.sh` wäre $HOME sonst
# /root und wir würden im falschen Tree lesen/schreiben.
printer_cfg="$(user_dir)/printer_data/config/printer.cfg"

if [ ! -f "$printer_cfg" ]; then
    echo "Error: Configuration file $printer_cfg not found or not readable!"
    exit 1
fi

echo "Searching for MCU..."

mcu_info=$(find_mcu_in_config "$printer_cfg") || {
    echo "Error: Could not extract 'serial' or 'cpu' from any [mcu] section reachable from $printer_cfg!"
    exit 1
}
serial=$(echo "$mcu_info" | sed -n 's/^serial=//p')
cpu=$(echo "$mcu_info" | sed -n 's/^cpu=//p')

if [ -z "$serial" ] || [ -z "$cpu" ]; then
    echo "Error: Could not extract 'serial' or 'cpu' from the [mcu] section reachable from $printer_cfg!"
    exit 1
fi

board=$(basename "$serial")

# Board-Verzeichnis liegt unter config/boards/<board> relativ zum scripts/.
board_dir=$(realpath "$current_dir/../config/boards/$board" 2>/dev/null || true)

if [ -z "$board_dir" ] || [ ! -d "$board_dir" ]; then
    echo "Error: $board not supported!"
    exit 1
fi

source_file="$board_dir/firmware.config"
target_file="$(user_dir)/klipper/.config"

if [ -f "$source_file" ]; then
    echo "Copying firmware.config for board $board to $target_file"
    cp "$source_file" "$target_file" || {
        echo "Error: Failed to copy firmware.config for board $board"
        exit 1
    }
else
    echo "Error: Source file $source_file for board $board does not exist!"
    exit 1
fi

pushd "$(user_dir)/klipper" > /dev/null || exit

echo "Building Klipper Firmware..."
make

echo "Looking for MCU: Serial=$serial, CPU=$cpu, Board=$board"

if [ -e "$serial" ]; then
    echo "MCU found at $serial"
else
    matching_devices=($(ls /dev/serial/by-id/usb-Klipper_*"$cpu"*-if00 2>/dev/null))

    if [ ${#matching_devices[@]} -eq 1 ]; then
        serial="${matching_devices[0]}"
        echo "MCU found at $serial"
    elif [ ${#matching_devices[@]} -gt 1 ]; then
        echo "Error: Multiple MCUs found:"
        for device in "${matching_devices[@]}"; do
            echo "  - $device"
        done
        popd > /dev/null
        exit 1
    fi
fi

# Erster Flash-Versuch über Serial. Exit-Code von `make flash` zählt:
# wait_for_mcu_reboot prüft nur die Symlink-Existenz, was bei einem
# laufenden Drucker immer wahr ist — ohne Exit-Code-Check würde ein
# fehlgeschlagener Flash als Erfolg gemeldet.
if [ -e "$serial" ]; then
    echo "Flashing $serial..."
    if make flash FLASH_DEVICE="$serial" NOSUDO=1 > /dev/null 2>&1 \
       && wait_for_mcu_reboot "$board"; then
        echo "Flashing successful."
        popd > /dev/null
        exit 0
    fi
fi

# --auto-Modus: kein DFU-Fallback, fail-fast.
if [ "$auto_mode" -eq 1 ]; then
    echo "Serial flash failed in --auto mode, not entering DFU loop."
    popd > /dev/null
    exit 1
fi

echo "Cannot Flash Board through serial mode, trying DFU mode..."
echo "Please Reboot your $board in DFU mode..."

MAX_WAIT=300
elapsed=0
while [ $elapsed -lt $MAX_WAIT ]; do
    OUTPUT=$(lsusb | grep "Device in DFU Mode")
    if [ -n "$OUTPUT" ]; then
        serial=$(echo "$OUTPUT" | awk '{print $6}')
        echo "MCU found at $serial"
        echo "Flashing $serial..."
        if make flash FLASH_DEVICE="$serial" NOSUDO=1 > /dev/null 2>&1 \
           && wait_for_mcu_reboot "$board"; then
            echo "Flashing successful."
            popd > /dev/null
            exit 0
        fi
        OUTPUT=$(lsusb | grep "Device in DFU Mode")
        if [ -n "$OUTPUT" ]; then
            echo "Board still in DFU, reflashing..."
            serial=$(echo "$OUTPUT" | awk '{print $6}')
            if make flash FLASH_DEVICE="$serial" NOSUDO=1 > /dev/null 2>&1 \
               && wait_for_mcu_reboot "$board"; then
                echo "Flashing successful."
                popd > /dev/null
                exit 0
            fi
            echo "Flashing failed."
            popd > /dev/null
            exit 1
        fi
    fi
    sleep 1
    ((elapsed++))
done

echo "No board found in DFU Mode, exiting"
popd > /dev/null
exit 1
