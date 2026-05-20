#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

F_TESTS_RUN=0
F_TESTS_FAILED=0

f_assert_eq() {
    local expected=$1 actual=$2 label=$3
    F_TESTS_RUN=$((F_TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  ok  - $label"
    else
        F_TESTS_FAILED=$((F_TESTS_FAILED + 1))
        echo "  FAIL - $label"
        echo "         expected: '$expected'"
        echo "         actual:   '$actual'"
    fi
}

# Build a fake environment: a fake klipper tree with a stub Makefile that
# (a) succeeds for plain 'make' and (b) fails for 'make flash …'.
# parse_mcu.sh is short-circuited via a fake printer.cfg + a known
# serial/cpu pair.
_setup_fake_env() {
    local tmp=$1
    mkdir -p "$tmp/klipper"
    mkdir -p "$tmp/THE100-Configuration/config/boards/fake-board"
    mkdir -p "$tmp/THE100-Configuration/scripts/helpers"
    mkdir -p "$tmp/printer_data/config"
    mkdir -p "$tmp/logs"
    mkdir -p "$tmp/bin"
    mkdir -p "$tmp/fake-dev"
    : > "$tmp/THE100-Configuration/config/boards/fake-board/firmware.config"
    # printer.cfg points at a serial path that REALLY EXISTS in the fake
    # env. flash.sh derives the board from basename($serial), so the
    # symlink basename MUST be "fake-board" — matching the boards/
    # directory above.
    : > "$tmp/fake-dev/.target"
    ln -s "$tmp/fake-dev/.target" "$tmp/fake-dev/fake-board"
    cat > "$tmp/printer_data/config/printer.cfg" <<EOF
[mcu]
serial: $tmp/fake-dev/fake-board
cpu: fakecpu
EOF
    cat > "$tmp/klipper/Makefile" <<'EOF'
.PHONY: all flash
all:
	@true
flash:
	@echo "stub flash failing intentionally" >&2 ; exit 1
EOF
    cat > "$tmp/bin/systemctl" <<'EOF'
#!/bin/bash
exit 0
EOF
    cat > "$tmp/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
    chmod +x "$tmp/bin/systemctl" "$tmp/bin/sudo"

    cp "$REPO_ROOT/scripts/flash.sh" "$tmp/THE100-Configuration/scripts/"
    cp "$REPO_ROOT/scripts/utils.sh" "$tmp/THE100-Configuration/scripts/"
    for h in parse_mcu.sh log.sh user_dir.sh current_user.sh; do
        cp "$REPO_ROOT/scripts/helpers/$h" \
           "$tmp/THE100-Configuration/scripts/helpers/"
    done
}

test_flash_auto_skips_dfu_on_serial_fail() {
    echo "test_flash_auto_skips_dfu_on_serial_fail:"
    local tmp; tmp=$(mktemp -d)
    _setup_fake_env "$tmp"

    local log="$tmp/logs/run.log"
    HOME="$tmp" \
        SUDO_USER="" BASE_USER="" \
        PATH="$tmp/bin:$PATH" \
        THEOS_BYPASS_ROOT_CHECK=1 \
        timeout 15 bash \
        "$tmp/THE100-Configuration/scripts/flash.sh" --auto \
        >"$log" 2>&1
    local rc=$?

    f_assert_eq "1" "$rc" "exit code 1 on serial flash failure"

    # The --auto path prints a discriminator message on serial-flash
    # failure. Asserting that message forces the test to fail unless
    # flash.sh actually reaches its serial-flash branch in --auto mode —
    # discriminates against any earlier exit (root check, printer.cfg
    # path, board lookup) that would also exit 1 without DFU.
    F_TESTS_RUN=$((F_TESTS_RUN + 1))
    if grep -q "Serial flash failed in --auto" "$log"; then
        echo "  ok  - --auto path produced fail-fast message"
    else
        F_TESTS_FAILED=$((F_TESTS_FAILED + 1))
        echo "  FAIL - --auto path was never reached"
        sed 's/^/         > /' "$log"
    fi

    # Match the DFU-loop entry strings the manual mode prints — but not the
    # --auto fail-fast message which also mentions DFU.
    if grep -qE "(trying DFU mode|Reboot your .* in DFU mode|Device in DFU Mode)" "$log"; then
        F_TESTS_FAILED=$((F_TESTS_FAILED + 1))
        echo "  FAIL - DFU loop entered under --auto"
        sed 's/^/         > /' "$log"
    else
        F_TESTS_RUN=$((F_TESTS_RUN + 1))
        echo "  ok  - DFU loop not entered under --auto"
    fi

    rm -rf "$tmp"
}

test_flash_auto_mode() {
    echo "Starting flash --auto tests..."
    test_flash_auto_skips_dfu_on_serial_fail
    echo
    echo "flash --auto tests: $((F_TESTS_RUN - F_TESTS_FAILED))/$F_TESTS_RUN passed"
    [ "$F_TESTS_FAILED" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_flash_auto_mode
fi
