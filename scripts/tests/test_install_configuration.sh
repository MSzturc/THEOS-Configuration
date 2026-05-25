#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

IC_TESTS_RUN=0
IC_TESTS_FAILED=0

ic_assert() {
    local rc=$1 label=$2
    IC_TESTS_RUN=$((IC_TESTS_RUN + 1))
    if [ "$rc" -eq 0 ]; then
        echo "  ok  - $label"
    else
        IC_TESTS_FAILED=$((IC_TESTS_FAILED + 1))
        echo "  FAIL - $label"
    fi
}

# Build a throwaway HOME holding the installer, its helpers, a recording `sudo`
# stub, and a marker-touching install-printer-cfg.sh stub.
_setup_install_env() {
    local tmp=$1
    mkdir -p "$tmp/THEOS-Configuration/scripts/helpers" "$tmp/bin"
    cp "$REPO_ROOT/scripts/install-configuration.sh" "$tmp/THEOS-Configuration/scripts/"
    cp "$REPO_ROOT/scripts/utils.sh"                 "$tmp/THEOS-Configuration/scripts/"
    for h in log.sh user_dir.sh current_user.sh; do
        cp "$REPO_ROOT/scripts/helpers/$h" "$tmp/THEOS-Configuration/scripts/helpers/"
    done
    cat > "$tmp/bin/sudo" <<EOF
#!/bin/bash
echo "\$@" >> "$tmp/sudo.log"
EOF
    chmod +x "$tmp/bin/sudo"
    cat > "$tmp/THEOS-Configuration/scripts/install-printer-cfg.sh" <<EOF
#!/bin/bash
touch "$tmp/printer-cfg-ran"
EOF
    chmod +x "$tmp/THEOS-Configuration/scripts/install-printer-cfg.sh"
}

_run_installer() {
    local tmp=$1 imgbuild=$2
    PATH="$tmp/bin:$PATH" HOME="$tmp" SUDO_USER="" BASE_USER="" \
        THEOS_IMAGE_BUILD="$imgbuild" \
        bash "$tmp/THEOS-Configuration/scripts/install-configuration.sh" \
        >/dev/null 2>&1
}

test_dev_run_is_nopasswd_safe() {
    echo "test_dev_run_is_nopasswd_safe:"
    local tmp; tmp=$(mktemp -d)
    _setup_install_env "$tmp"
    _run_installer "$tmp" ""

    local n; n=$(grep -c 'update-.*\.sh' "$tmp/sudo.log" 2>/dev/null)
    ic_assert "$([ "$n" -eq 3 ] && echo 0 || echo 1)" "the 3 privileged update scripts run via sudo (got $n)"

    grep -q 'THEOS_IMAGE_BUILD' "$tmp/sudo.log" 2>/dev/null
    ic_assert "$([ $? -ne 0 ] && echo 0 || echo 1)" "no THEOS_IMAGE_BUILD env prefix on sudo when unset"

    ic_assert "$([ -f "$tmp/printer-cfg-ran" ] && echo 0 || echo 1)" "install-printer-cfg.sh actually ran"

    grep -q 'install-printer-cfg' "$tmp/sudo.log" 2>/dev/null
    ic_assert "$([ $? -ne 0 ] && echo 0 || echo 1)" "install-printer-cfg.sh is not run through sudo"

    rm -rf "$tmp"
}

test_image_build_forwards_env() {
    echo "test_image_build_forwards_env:"
    local tmp; tmp=$(mktemp -d)
    _setup_install_env "$tmp"
    _run_installer "$tmp" "1"

    local n; n=$(grep -c 'THEOS_IMAGE_BUILD=1' "$tmp/sudo.log" 2>/dev/null)
    ic_assert "$([ "$n" -eq 3 ] && echo 0 || echo 1)" "THEOS_IMAGE_BUILD=1 forwarded to the 3 privileged scripts (got $n)"

    rm -rf "$tmp"
}

test_install_configuration() {
    echo "Starting install_configuration tests..."
    test_dev_run_is_nopasswd_safe
    test_image_build_forwards_env
    echo
    echo "install_configuration tests: $((IC_TESTS_RUN - IC_TESTS_FAILED))/$IC_TESTS_RUN passed"
    [ "$IC_TESTS_FAILED" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_install_configuration
fi
