#!/bin/bash
# version.sh — helpers for the firmware-auto-flash workflow.
#
# parse_klipper_version <string>
#   Sets the caller-visible variables `major`, `minor`, `patch` from a
#   git-describe-style version (e.g. "v0.13.1-5-gabcdef12-dirty"). Returns
#   non-zero and clears the variables when the input does not start with
#   "v<int>.<int>.<int>" (i.e. when git describe fell back to an
#   abbreviated SHA or the input is empty).
#
# read_mcu_version_from_log [<path>]
#   Prints the VERSION field of the last "Loaded MCU 'mcu' …" line in the
#   given klippy.log (default ~/printer_data/logs/klippy.log). Prints an
#   empty string when the log is missing or contains no such line.

parse_klipper_version() {
    local input=$1
    major=""; minor=""; patch=""
    if [[ "$input" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)([-.].*)?$ ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
        return 0
    fi
    return 1
}

read_mcu_version_from_log() {
    local log=${1:-$HOME/printer_data/logs/klippy.log}
    [ -f "$log" ] || { printf ''; return 0; }
    # Grab the last "Loaded MCU 'mcu' N commands (VERSION / BUILD)" line
    # and extract VERSION (first token inside the parens). Single-quoted
    # 'mcu' ensures secondary MCUs like 'adxl' are ignored.
    awk -F'[()]' "
        /Loaded MCU 'mcu' / {
            n = split(\$2, parts, \" / \")
            if (n >= 1) last = parts[1]
        }
        END { if (last) print last }
    " "$log"
}
