#!/bin/bash

# Git provides three positional args to a post-checkout hook:
#   $1 = previous HEAD, $2 = new HEAD, $3 = checkout type
#   (1 = branch/commit-checkout, 0 = file-checkout)
prev_ref=$1
new_ref=$2
checkout_type=$3

[[ "$checkout_type" -eq 1 ]] || exit 0
[[ "$prev_ref" != "$new_ref" ]] || exit 0

SCRIPT_DIR=$( cd -- "$( dirname -- "$(realpath -- "${BASH_SOURCE[0]}")" )" &> /dev/null && pwd )
sudo "$SCRIPT_DIR"/update-klipper.sh
