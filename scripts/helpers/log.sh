#!/bin/bash

# Global variable to store the last used timestamp
LAST_FILE_TIMESTAMP=""
LAST_CONSOLE_TIMESTAMP=""

# Logging function with precise alignment of log levels
log() {
    local logs_dir
    logs_dir="$(user_dir)/logs"

    # Ensure logs directory exists BEFORE any file access
    mkdir -p "$logs_dir"

    LOG_FILE="$logs_dir/theos.log"
    LAST_DAY_FILE="$logs_dir/last_day_checked"

    local level="$1"
    local color="$2"
    local text="$3"
    local caller
    local timestamp
    local current_day

    # Determine the caller function/file
    caller=$(caller 1 | awk '{print $2}')
    caller="[$(printf "%-22s" "$caller")]"

    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    current_day=$(date +"%Y-%m-%d")

    # Initialize last_day_checked if missing/empty
    if [ ! -s "$LAST_DAY_FILE" ]; then
        printf "%s\n" "$current_day" > "$LAST_DAY_FILE"
    fi

    # Read the last checked day from the file
    LAST_DAY_CHECKED="$(cat "$LAST_DAY_FILE" 2>/dev/null || true)"
    if [ -z "$LAST_DAY_CHECKED" ]; then
        LAST_DAY_CHECKED="$current_day"
        printf "%s\n" "$current_day" > "$LAST_DAY_FILE"
    fi

    # Check if a new day has started and clear the log if so
    if [ "$current_day" != "$LAST_DAY_CHECKED" ]; then
        : > "$LOG_FILE"
        printf "%s\n" "$current_day" > "$LAST_DAY_FILE"
    fi

    # Fixed width for the timestamp and fixed width for the log level brackets
    local timestamp_width=22
    local level_width=10

    # Center the log level within the fixed width
    local level_padding=$(( (level_width - ${#level}) / 2 ))
    local padded_level="$(printf "%${level_padding}s%s%${level_padding}s" "" "$level" "")"

    # Append log to the log file with the caller in its own column
    if [ "$timestamp" != "$LAST_FILE_TIMESTAMP" ]; then
        printf "%-${timestamp_width}s[%-${level_width}s] %-24s %s\n" "[$timestamp]" "$padded_level" "$caller" "$text" >> "$LOG_FILE"
        LAST_FILE_TIMESTAMP="$timestamp"
    else
        printf "%*s[%-${level_width}s] %-24s %s\n" ${timestamp_width} "" "$padded_level" "$caller" "$text" >> "$LOG_FILE"
    fi

    # Print to console only if not DEBUG or debugging is active
    if [ "$level" != "DEBUG" ] || [ -f "$logs_dir/debugging.active" ]; then
        if [ "$timestamp" != "$LAST_CONSOLE_TIMESTAMP" ]; then
            printf "%-${timestamp_width}s%b[%-${level_width}s]\e[0m %s\n" "[$timestamp]" "$color" "$padded_level" "$text"
            LAST_CONSOLE_TIMESTAMP="$timestamp"
        else
            printf "%*s%b[%-${level_width}s]\e[0m %s\n" ${timestamp_width} "" "$color" "$padded_level" "$text"
        fi
    fi
}

# Individual functions for each log level
debug() {
    DEBUGGING_FILE="$(user_dir)/logs/debugging.active"
    log "DEBUG" "\e[36m" "$1"  # Cyan
}

info() {
    log "INFO" "\e[32m" "$1"  # Green
}

warning() {
    log "WARNING" "\e[33m" "$1"  # Yellow
}

error() {
    log "ERROR" "\e[31m" "$1"  # Red
}

check() {
    log "CHECK" "\e[32m" "$1"  # Green (same as INFO, but for checks)
}

# Function to enable debugging
enable_debugging() {
    DEBUGGING_FILE="$(user_dir)/logs/debugging.active"
    mkdir -p "$(user_dir)/logs"
    touch "$DEBUGGING_FILE"
    info "Debugging enabled."
}

# Function to disable debugging
disable_debugging() {
    DEBUGGING_FILE="$(user_dir)/logs/debugging.active"
    if [ -f "$DEBUGGING_FILE" ]; then
        rm "$DEBUGGING_FILE"
        info "Debugging disabled."
    fi
}
