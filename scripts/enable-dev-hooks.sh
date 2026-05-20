#!/bin/bash

# Enable maintainer-only git hooks in ~/klipper that turn `git checkout <tag>`
# into a trigger for the full update path (including auto-flash). Called
# from run.sh; never installed by install-configuration.sh.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR"/utils.sh

KLIPPER_PATH="$(user_dir)/klipper"
hook_target="$SCRIPT_DIR/post-checkout-klipper.sh"
hook_link="$KLIPPER_PATH/.git/hooks/post-checkout"

if [[ ! -d "$KLIPPER_PATH/.git/hooks" ]]; then
    error "Cannot enable dev hooks: $KLIPPER_PATH/.git/hooks is missing."
    exit 1
fi

if [[ -L "$hook_link" ]] && [[ "$(readlink "$hook_link")" = "$hook_target" ]]; then
    info "Dev post-checkout hook already enabled."
    exit 0
fi

# Replace anything (file, broken symlink, wrong-target symlink) at the path.
rm -f "$hook_link"
ln -s "$hook_target" "$hook_link"
info "Dev post-checkout hook enabled → $hook_link"
