#!/bin/bash

# Maintainer dev-loop: sync ~/klipper to origin/develop, hard-reset the
# THEOS-Configuration to a known baseline, reinstall the configuration,
# and re-enable the dev-only post-checkout hook.
#
# IMPORTANT: this script removes the post-checkout hook at the top BEFORE
# any `git checkout` happens — otherwise an already-installed hook from a
# previous run would re-enter the full update path mid-script.

HOOK_PATH=~/klipper/.git/hooks/post-checkout
if [[ -e "$HOOK_PATH" || -L "$HOOK_PATH" ]]; then
    rm -f "$HOOK_PATH" || { echo "ERROR: cannot remove $HOOK_PATH"; exit 1; }
fi
if [[ -e "$HOOK_PATH" || -L "$HOOK_PATH" ]]; then
    echo "ERROR: $HOOK_PATH still present after rm -f"
    exit 1
fi

rm -rf ~/printer_data/logs/klippy.log
touch ~/printer_data/logs/klippy.log
chown pi:pi ~/printer_data/logs/klippy.log
chmod 666 ~/printer_data/logs/klippy.log

rm -rf ~/logs/theos.log
touch ~/logs/theos.log
chown pi:pi ~/logs/theos.log
chmod 666 ~/logs/theos.log

cd ~/klipper/
git checkout develop
git reset --hard origin/develop
git pull

cd ~/THEOS-Configuration/
git checkout develop
git reset --hard origin/develop
git pull
./scripts/install-configuration.sh

./scripts/enable-dev-hooks.sh
