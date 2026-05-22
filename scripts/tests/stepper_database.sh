#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

test_stepper_database() {
    echo "Starting stepper database tests..."
    local py=""
    for cand in python3 python; do
        if command -v "$cand" >/dev/null 2>&1 \
           && "$cand" -c "import sys" >/dev/null 2>&1; then
            py="$cand"; break
        fi
    done
    if [ -z "$py" ]; then
        echo "  SKIP - working python interpreter not found on PATH"; return 0
    fi
    "$py" "$SCRIPT_DIR/test_stepper_database.py" -v
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_stepper_database
fi
