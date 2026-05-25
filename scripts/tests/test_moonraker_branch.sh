#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/helpers/moonraker_branch.sh"

MB_TESTS_RUN=0
MB_TESTS_FAILED=0

mb_assert_equals() {
    local expected=$1 actual=$2 label=$3
    MB_TESTS_RUN=$((MB_TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  ok  - $label"
    else
        MB_TESTS_FAILED=$((MB_TESTS_FAILED + 1))
        echo "  FAIL - $label (expected '$expected', got '$actual')"
    fi
}

# Read the primary_branch value of a given [update_manager <section>] block.
_section_branch() {
    local conf=$1 section=$2
    awk -v header="[update_manager ${section}]" '
        /^\[/ { in_section = ($0 == header) }
        in_section && /^[[:space:]]*primary_branch[[:space:]]*:/ {
            sub(/^[[:space:]]*primary_branch[[:space:]]*:[[:space:]]*/, "")
            print; exit
        }
    ' "$conf"
}

_write_fixture() {
    cat > "$1" <<'EOF'
[update_manager mainsail-config]
type: git_repo
primary_branch: master
path: ~/mainsail-config

[update_manager THEOS-Configuration]
type: git_repo
channel: dev
path: ~/THEOS-Configuration
primary_branch: main

[update_manager sonar]
type: git_repo
primary_branch: main
EOF
}

test_flips_only_target_section() {
    echo "test_flips_only_target_section:"
    local tmp; tmp=$(mktemp -d)
    local conf="$tmp/moonraker.conf"
    _write_fixture "$conf"
    set_update_manager_branch "$conf" "THEOS-Configuration" "develop"
    mb_assert_equals 0 "$?" "returns success"
    mb_assert_equals "develop" "$(_section_branch "$conf" THEOS-Configuration)" "THEOS-Configuration flips to develop"
    mb_assert_equals "master"  "$(_section_branch "$conf" mainsail-config)"     "mainsail-config left untouched"
    mb_assert_equals "main"    "$(_section_branch "$conf" sonar)"               "sonar left untouched"
    rm -rf "$tmp"
}

test_idempotent() {
    echo "test_idempotent:"
    local tmp; tmp=$(mktemp -d)
    local conf="$tmp/moonraker.conf"
    _write_fixture "$conf"
    set_update_manager_branch "$conf" "THEOS-Configuration" "develop"
    local after1; after1=$(cat "$conf")
    set_update_manager_branch "$conf" "THEOS-Configuration" "develop"
    local rc=$?
    local after2; after2=$(cat "$conf")
    mb_assert_equals 0 "$rc" "second run returns success"
    mb_assert_equals "$after1" "$after2" "second run is a no-op"
    rm -rf "$tmp"
}

test_missing_section_returns_error() {
    echo "test_missing_section_returns_error:"
    local tmp; tmp=$(mktemp -d)
    local conf="$tmp/moonraker.conf"
    _write_fixture "$conf"
    local before; before=$(cat "$conf")
    set_update_manager_branch "$conf" "DoesNotExist" "develop"
    local rc=$?
    local after; after=$(cat "$conf")
    mb_assert_equals 1 "$rc" "unknown section returns error"
    mb_assert_equals "$before" "$after" "file unchanged for unknown section"
    rm -rf "$tmp"
}

test_moonraker_branch() {
    echo "Starting moonraker_branch tests..."
    test_flips_only_target_section
    test_idempotent
    test_missing_section_returns_error
    echo
    echo "moonraker_branch tests: $((MB_TESTS_RUN - MB_TESTS_FAILED))/$MB_TESTS_RUN passed"
    [ "$MB_TESTS_FAILED" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_moonraker_branch
fi
