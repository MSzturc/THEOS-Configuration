#!/bin/bash

# Where this Script is located
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR"/utils.sh
source "$SCRIPT_DIR"/helpers/version.sh
source "$SCRIPT_DIR"/helpers/parse_mcu.sh

# Where the Klipper folder is located
KLIPPER_PATH="$(user_dir)/klipper"

# Where the user Klipper config is located
KLIPPER_CONFIG_PATH="$(user_dir)/printer_data/config"

# Where to clone THEOS-Configuration repository
THEOS_CONFIG_PATH="$(user_dir)/THEOS-Configuration"

# Where the Moonraker folder is located
MOONRAKER_PATH="$(user_dir)/moonraker"

# Where the BD_Sensor folder is located
BD_SENSOR_PATH="$(user_dir)/Bed_Distance_sensor/klipper"

# Where the Shake&Tune folder is located
SHAKETUNE_PATH="$(user_dir)/klippain_shaketune"

# This function sets up git hooks for THEOS-Configuration, Klipper, and Moonraker.
# The post-merge hooks ensure that specific scripts are executed automatically
# after a 'git pull' or 'git merge' operation in each repository. We use it to reapply
# install scripts for different Klipper addons.
install_hooks()
{
    info "Installing git hooks..."

    # Check if the post-merge hook for THEOS-Configuration does not already exist as a symbolic link
    if [[ ! -L "$THEOS_CONFIG_PATH/.git/hooks/post-merge" ]]
    then
        # Create a symbolic link for the THEOS-Configuration post-merge script
        ln -s "$SCRIPT_DIR/post-merge-configuration.sh" "$THEOS_CONFIG_PATH/.git/hooks/post-merge"
        info "Post-merge hook set up for THEOS-Configuration."
    fi

    # Check if the post-merge hook for klipper does not already exist as a symbolic link
    if [[ ! -L "$KLIPPER_PATH/.git/hooks/post-merge" ]]
    then
        # Create a symbolic link for klipper post-merge script
        ln -s "$SCRIPT_DIR/post-merge-klipper.sh" "$KLIPPER_PATH/.git/hooks/post-merge"
        info "Post-merge hook set up for klipper."
    fi

    # Check if the post-merge hook for moonraker does not already exist as a symbolic link
    if [[ ! -L "$MOONRAKER_PATH/.git/hooks/post-merge" ]]
    then
        # Create a symbolic link for moonraker post-merge script
        ln -s "$SCRIPT_DIR/post-merge-moonraker.sh" "$MOONRAKER_PATH/.git/hooks/post-merge"
        info "Post-merge hook set up for moonraker."
    fi
}
install_shaketune_extension(){
    info "Installing Shake&Tune extension to klipper..."

    # Debug-Ausgabe: Pfade anzeigen
    debug "SHAKETUNE_PATH is set to '$SHAKETUNE_PATH'"
    debug "KLIPPER_PATH is set to '$KLIPPER_PATH'"

    # Check if shaketune directory does not already exist as a symbolic link
    if [[ ! -d "$KLIPPER_PATH/klippy/extras/shaketune" ]]
    then
        debug "Creating symbolic link for shaketune..."
        # Create a symbolic link for shaketune directory
        ln -frsn "$SHAKETUNE_PATH/shaketune" "${KLIPPER_PATH}/klippy/extras/shaketune"
        debug "Symbolic link for shaketune directory created."
    else
        debug "Symbolic link for shaketune directory already exists. Skipping."
    fi

    info "Shake&Tune extension installation completed."
}

enable_rt_runtime() {
    info "Enabling realtime scheduler..."
    local sysctl_file="/etc/sysctl.d/10-rt-runtime-disable.conf"

    if [[ -f "$sysctl_file" ]]; then
        info "Realtime scheduler activated."
    else
        echo "kernel.sched_rt_runtime_us=-1" > "$sysctl_file" 2>/dev/null
        info "Realtime scheduler activated."

        sysctl --system >/dev/null 2>&1
    fi
}

enable_rt_in_klipper_service() {
    info "Enabling realtime scheduler in klipper service..."
    local service_file="/etc/systemd/system/klipper.service"

    # Abbrechen, falls die Datei nicht existiert
    [[ ! -f "$service_file" ]] && return 0

    # Flag, um Änderungen zu tracken
    local changed=0

    # LimitRTPRIO=99 ergänzen, wenn noch nicht vorhanden
    if ! grep -q '^LimitRTPRIO=99' "$service_file"; then
        sed -i '/^User=pi$/a LimitRTPRIO=99' "$service_file" 2>/dev/null
        changed=1
    fi

    # AmbientCapabilities=CAP_SYS_NICE ergänzen, wenn noch nicht vorhanden
    if ! grep -q '^AmbientCapabilities=CAP_SYS_NICE' "$service_file"; then
        sed -i '/^User=pi$/a AmbientCapabilities=CAP_SYS_NICE' "$service_file" 2>/dev/null
        changed=1
    fi

    # Nur reloaden, wenn wir etwas geändert haben
    if [[ "$changed" -eq 1 ]]; then
        systemctl daemon-reload >/dev/null 2>&1
        info "Realtime scheduler activated (systemd daemon reloaded)."
    fi
}


# maybe_flash_firmware compares the klipper-source version (`git describe`)
# against the version the MCU last reported in klippy.log and, if the
# (major, minor, patch) fields differ, invokes flash.sh --auto. When
# either side cannot be parsed the function falls back to flashing.
# Boards without a firmware.config are reported and skipped.
maybe_flash_firmware() {
    local source_raw mcu_raw board
    local s_maj s_min s_pat m_maj m_min m_pat
    local soll_ok=1 ist_ok=1

    source_raw=$(git -C "$KLIPPER_PATH" describe --tags --always 2>/dev/null)
    if parse_klipper_version "$source_raw"; then
        s_maj=$major; s_min=$minor; s_pat=$patch
    else
        soll_ok=0
    fi

    mcu_raw=$(read_mcu_version_from_log "$(user_dir)/printer_data/logs/klippy.log")
    if [ -n "$mcu_raw" ] && parse_klipper_version "$mcu_raw"; then
        m_maj=$major; m_min=$minor; m_pat=$patch
    else
        ist_ok=0
    fi

    local printer_cfg="$(user_dir)/printer_data/config/printer.cfg"
    if [ ! -f "$printer_cfg" ]; then
        info "maybe_flash_firmware: printer.cfg missing at $printer_cfg, skipping"
        return 0
    fi
    local mcu_info
    mcu_info=$(find_mcu_in_config "$printer_cfg") || {
        info "maybe_flash_firmware: cannot determine [mcu] board, skipping"
        return 0
    }
    local serial; serial=$(echo "$mcu_info" | sed -n 's/^serial=//p')
    board=$(basename "$serial")

    local fw_config="$THEOS_CONFIG_PATH/config/boards/$board/firmware.config"
    if [ ! -f "$fw_config" ]; then
        info "Automatic firmware update not supported for board $board (no firmware.config)"
        return 0
    fi

    if [ "$soll_ok" -eq 0 ] || [ "$ist_ok" -eq 0 ]; then
        info "Version compare not possible (source=$source_raw, mcu=$mcu_raw) — flashing as fallback"
    elif [ "$s_maj" = "$m_maj" ] && [ "$s_min" = "$m_min" ] && [ "$s_pat" = "$m_pat" ]; then
        info "MCU firmware up-to-date (source=$source_raw, mcu=$mcu_raw)"
        return 0
    else
        info "Version drift detected (source=$source_raw, mcu=$mcu_raw) — flashing"
    fi

    if "$SCRIPT_DIR"/flash.sh --auto; then
        info "Flash succeeded"
    else
        error "Flash failed; restart_klipper_service will still try to bring host up"
    fi
}

preflight_checks() {
    ensure_root
    is_klipper_installed
    is_moonraker_installed
    is_configuration_installed
}

# Allow tests to source this file without executing the main block.
# The guard sits AFTER every function definition so a sourced test script
# can call them directly.
if [ -n "${THEOS_LIBRARY_MODE:-}" ]; then
    return 0
fi

preflight_checks
install_hooks
install_shaketune_extension
enable_rt_runtime
enable_rt_in_klipper_service

# THEOS_IMAGE_BUILD is set during the CustoPiZer chroot build, where there
# is no MCU to flash and systemd is not running. Skip the hardware path
# entirely; the next regular `git pull` on the printer drives the flash.
if [ -n "${THEOS_IMAGE_BUILD:-}" ]; then
    info "Image-build mode: skipping firmware flash and Klipper restart."
else
    systemctl stop klipper >/dev/null 2>&1 || true
    maybe_flash_firmware
    restart_klipper_service
fi
