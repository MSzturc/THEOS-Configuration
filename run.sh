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
# days-old) ref the released image was built with. `checkout -f` because the
# released image tracks main where the installer's chmod +x dirties tracked
# .sh files — a plain checkout would refuse the switch and leave a half-state.
for repo in ~/klipper ~/THEOS-Configuration; do
    cd "$repo"
    git fetch origin
    git checkout -f develop
    git reset --hard origin/develop
done

~/THEOS-Configuration/scripts/install-configuration.sh
~/THEOS-Configuration/scripts/enable-dev-hooks.sh

# Point Moonraker's update manager at develop: the shipped image tracks main,
# so a dev checkout otherwise trips its "not on official remote/branch" guard.
# Restart via Moonraker's own API — the dev-loop has no passwordless systemctl.
MOONRAKER_BRANCH_HELPER=~/THEOS-Configuration/scripts/helpers/moonraker_branch.sh
MOONRAKER_CONF=~/printer_data/config/moonraker.conf
if [[ -f "$MOONRAKER_BRANCH_HELPER" && -f "$MOONRAKER_CONF" ]]; then
    source "$MOONRAKER_BRANCH_HELPER"
    if set_update_manager_branch "$MOONRAKER_CONF" THEOS-Configuration develop; then
        curl -sf -X POST \
            "http://localhost:7125/machine/services/restart?service=moonraker" \
            >/dev/null 2>&1 || true
    fi
fi
