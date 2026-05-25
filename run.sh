#!/bin/bash
set -euo pipefail

# Maintainer dev-loop: turn an officially released image into developer mode —
# move our forks (~/klipper, ~/THEOS-Configuration) onto their develop branches,
# force them to match origin, reinstall the configuration, and re-enable the
# dev-only post-checkout hook.
#
# IMPORTANT: remove the post-checkout hook BEFORE any `git checkout` — an
# already-installed hook from a previous run would otherwise re-enter the full
# update path mid-script.
# WARNING: `git reset --hard` discards local changes in both repos.

HOOK_PATH=~/klipper/.git/hooks/post-checkout
if [[ -e "$HOOK_PATH" || -L "$HOOK_PATH" ]]; then
    rm -f "$HOOK_PATH" || { echo "ERROR: cannot remove $HOOK_PATH"; exit 1; }
fi
if [[ -e "$HOOK_PATH" || -L "$HOOK_PATH" ]]; then
    echo "ERROR: $HOOK_PATH still present after rm -f"
    exit 1
fi

# Reset the logs we tail during a dev loop. Ownership/permission fixes are
# best-effort: a stale root-owned log must not abort the run under set -e.
for log in ~/printer_data/logs/klippy.log ~/logs/theos.log; do
    mkdir -p "$(dirname "$log")"
    rm -f "$log"
    touch "$log"
    chown pi:pi "$log" 2>/dev/null || true
    chmod 666 "$log" 2>/dev/null || true
done

# Our forks: move onto develop and force them to match origin exactly. Fetch
# first so the reset targets the current remote tip, not the (possibly
# days-old) ref the released image was built with.
for repo in ~/klipper ~/THEOS-Configuration; do
    cd "$repo"
    git fetch origin
    git checkout develop
    git reset --hard origin/develop
done

~/THEOS-Configuration/scripts/install-configuration.sh
~/THEOS-Configuration/scripts/enable-dev-hooks.sh
