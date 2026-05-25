#!/bin/bash

# Where this Script is located
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR"/utils.sh

# Where the Klipper folder is located
KLIPPER_PATH="$(user_dir)/klipper"

# Where the user Klipper config is located
KLIPPER_CONFIG_PATH="$(user_dir)/printer_data/config"

# Where to clone THEOS-Configuration repository
THEOS_CONFIG_PATH="$(user_dir)/THEOS-Configuration"

# Where the Moonraker folder is located
MOONRAKER_PATH="$(user_dir)/moonraker"

# Branch from MSzturc/THEOS-Configuration repo to use during install (default: main)
THEOS_CONFIG_REPOSITORY="https://github.com/MSzturc/THEOS-Configuration.git"

# Branch from MSzturc/THEOS-Configuration repo to use during install (default: main)
THEOS_CONFIG_BRANCH="main"

download_configuration() {
    
    if [ -d "$THEOS_CONFIG_PATH" ]; then
        info "Configuration repository already found locally at $THEOS_CONFIG_PATH. Skipping download."
    else
        info "Configuration repository does not exist at $THEOS_CONFIG_PATH. Cloning repository..."
        if git clone --quiet --branch "$THEOS_CONFIG_BRANCH" "$THEOS_CONFIG_REPOSITORY" "$THEOS_CONFIG_PATH"; then
            check "Successfully cloned configuration repository to $THEOS_CONFIG_PATH."
        else
            error "Failed to clone configuration repository."
            exit 1
        fi
    fi
}

# This function checks if a 'logs' directory exists in the user's home directory.
# If it doesn't exist, the function creates the directory and sets its permissions to allow 
# read and write access for all users. Additionally, it creates an empty 'theos.log' file 
# in the directory with the same permissions.
install_logs() {

    # Path to the logs directory
    local logs_dir="$(user_dir)/logs"
    local log_file="$logs_dir/theos.log"

    # Check if the 'logs' folder exists
    if [ ! -d "$logs_dir" ]; then
        info "Creating folder: $logs_dir"
        mkdir "$logs_dir"
    else
        debug "Folder already exists: $logs_dir"
    fi

    # Set permissions: read and write for all users (folder and future files)
    chmod 777 "$logs_dir"
    info "Permissions for folder $logs_dir set: read and write for all users."

    # Check if the file 'theos.log' exists, otherwise create it
    if [ ! -f "$log_file" ]; then
        debug "Creating file: $log_file"
        touch "$log_file"
    else
        debug "File already exists: $log_file"
    fi

    # Set permissions: read and write for all users for the file
    chmod 666 "$log_file"
    info "Permissions for file $log_file set: read and write for all users."
}

preflight_checks() {
    ensure_not_root
}

preflight_checks
download_configuration
install_logs

# THEOS_IMAGE_BUILD lets update-klipper.sh skip the hardware-bound steps
# (firmware flash + systemctl restart) inside the CustoPiZer chroot. Forward it
# only when set: on the printer a `sudo VAR= script` prefix misses the NOPASSWD
# sudoers rules (env vars are not in env_keep) and forces a password prompt,
# breaking the passwordless dev-loop and Moonraker update path.
sudo_env=()
[[ -n "${THEOS_IMAGE_BUILD:-}" ]] && sudo_env=(THEOS_IMAGE_BUILD="${THEOS_IMAGE_BUILD}")

sudo "${sudo_env[@]}" "$SCRIPT_DIR"/update-configuration.sh
sudo "${sudo_env[@]}" "$SCRIPT_DIR"/update-klipper.sh
sudo "${sudo_env[@]}" "$SCRIPT_DIR"/update-moonraker.sh

# install-printer-cfg.sh only writes the invoking user's own printer_data, so it
# needs no root — and install-configuration.sh always runs as that user (the
# image build invokes it via `sudo -u`). A direct call keeps the right ownership
# and avoids a password prompt (it is not in the NOPASSWD list).
"$SCRIPT_DIR"/install-printer-cfg.sh
