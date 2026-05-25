#!/bin/bash
# moonraker_branch.sh — dev-loop helper for moonraker.conf.
#
# set_update_manager_branch <conf> <section> <branch>
#   Rewrites the `primary_branch:` line inside the `[update_manager <section>]`
#   block of <conf> to <branch>, leaving every other section and the rest of
#   the file byte-for-byte intact (the file holds several update_manager blocks
#   with their own primary_branch values). Idempotent. Returns non-zero when
#   <conf> is missing or the section carries no primary_branch line to rewrite.

set_update_manager_branch() {
    local conf=$1 section=$2 branch=$3
    [ -f "$conf" ] || return 1

    awk -v header="[update_manager ${section}]" -v branch="$branch" '
        /^\[/ { in_section = ($0 == header) }
        in_section && /^[[:space:]]*primary_branch[[:space:]]*:/ {
            print "primary_branch: " branch
            changed = 1
            next
        }
        { print }
        END { exit (changed ? 0 : 1) }
    ' "$conf" > "${conf}.tmp"
    local rc=$?

    if [ "$rc" -ne 0 ]; then
        rm -f "${conf}.tmp"
        return 1
    fi

    # Replace content in place so the original owner/mode survive.
    cat "${conf}.tmp" > "$conf"
    rm -f "${conf}.tmp"
    return 0
}
