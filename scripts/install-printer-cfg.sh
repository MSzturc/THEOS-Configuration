#!/bin/bash
# Install the wizard-mode bootstrap printer.cfg on a fresh system.
# One-shot: never overwrites an existing printer.cfg (the wizard owns it after
# first run). No hostname/template logic — the wizard picks the hardware.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR"/utils.sh

PRINTER_CFG="$(user_dir)/printer_data/config/printer.cfg"
BOOTSTRAP="$SCRIPT_DIR/../config/bootstrap/wizard.cfg"

if [[ -f "$PRINTER_CFG" ]]; then
    info "printer.cfg already exists — leaving it untouched."
    exit 0
fi

if [[ ! -f "$BOOTSTRAP" ]]; then
    error "Bootstrap config not found at $BOOTSTRAP"
    exit 1
fi

info "No printer.cfg found — installing wizard-mode bootstrap config."
mkdir -p "$(dirname "$PRINTER_CFG")"
cp "$BOOTSTRAP" "$PRINTER_CFG"
chown "$(current_user):$(current_user)" "$PRINTER_CFG" 2>/dev/null || true
chmod 644 "$PRINTER_CFG"
info "Wizard-mode bootstrap installed. Run SETUP_WIZARD on first boot."
