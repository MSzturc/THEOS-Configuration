#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

P_TESTS_RUN=0
P_TESTS_FAILED=0

p_assert_called() {
    local marker=$1 label=$2
    P_TESTS_RUN=$((P_TESTS_RUN + 1))
    if [ -f "$marker" ]; then
        echo "  ok  - $label"
    else
        P_TESTS_FAILED=$((P_TESTS_FAILED + 1))
        echo "  FAIL - $label (expected $marker)"
    fi
}

p_assert_not_called() {
    local marker=$1 label=$2
    P_TESTS_RUN=$((P_TESTS_RUN + 1))
    if [ ! -f "$marker" ]; then
        echo "  ok  - $label"
    else
        P_TESTS_FAILED=$((P_TESTS_FAILED + 1))
        echo "  FAIL - $label (unexpected $marker)"
    fi
}

_run_hook_with_stub() {
    local args=("$1" "$2" "$3")
    local tmp=$4 marker=$5

    mkdir -p "$tmp/scripts"
    cp "$REPO_ROOT/scripts/post-checkout-klipper.sh" "$tmp/scripts/"
    cat > "$tmp/scripts/update-klipper.sh" <<EOF
#!/bin/bash
touch "$marker"
EOF
    chmod +x "$tmp/scripts/update-klipper.sh"
    mkdir -p "$tmp/bin"
    cat > "$tmp/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
    chmod +x "$tmp/bin/sudo"

    PATH="$tmp/bin:$PATH" bash "$tmp/scripts/post-checkout-klipper.sh" \
        "${args[@]}" >/dev/null 2>&1
}

test_branch_checkout_invokes_update() {
    echo "test_branch_checkout_invokes_update:"
    local tmp; tmp=$(mktemp -d)
    local marker="$tmp/called"
    _run_hook_with_stub "abc" "def" "1" "$tmp" "$marker"
    p_assert_called "$marker" "branch checkout (1, old!=new) → update-klipper called"
    rm -rf "$tmp"
}

test_file_checkout_skipped() {
    echo "test_file_checkout_skipped:"
    local tmp; tmp=$(mktemp -d)
    local marker="$tmp/called"
    _run_hook_with_stub "abc" "def" "0" "$tmp" "$marker"
    p_assert_not_called "$marker" "file checkout (0) → update-klipper NOT called"
    rm -rf "$tmp"
}

test_same_ref_skipped() {
    echo "test_same_ref_skipped:"
    local tmp; tmp=$(mktemp -d)
    local marker="$tmp/called"
    _run_hook_with_stub "abc" "abc" "1" "$tmp" "$marker"
    p_assert_not_called "$marker" "same-ref checkout (old==new) → update-klipper NOT called"
    rm -rf "$tmp"
}

test_enable_dev_hooks_idempotent() {
    echo "test_enable_dev_hooks_idempotent:"
    local tmp; tmp=$(mktemp -d)
    mkdir -p "$tmp/klipper/.git/hooks"
    mkdir -p "$tmp/THEOS-Configuration/scripts/helpers"
    mkdir -p "$tmp/logs"
    cp "$REPO_ROOT/scripts/enable-dev-hooks.sh" "$tmp/THEOS-Configuration/scripts/"
    cp "$REPO_ROOT/scripts/utils.sh"            "$tmp/THEOS-Configuration/scripts/"
    cp "$REPO_ROOT/scripts/post-checkout-klipper.sh" \
       "$tmp/THEOS-Configuration/scripts/"
    for h in log.sh user_dir.sh current_user.sh; do
        cp "$REPO_ROOT/scripts/helpers/$h" \
           "$tmp/THEOS-Configuration/scripts/helpers/"
    done

    HOME="$tmp" SUDO_USER="" BASE_USER="" \
        bash "$tmp/THEOS-Configuration/scripts/enable-dev-hooks.sh" \
        >/dev/null 2>&1
    local rc1=$?
    P_TESTS_RUN=$((P_TESTS_RUN + 1))
    if [ "$rc1" -eq 0 ] && [ -L "$tmp/klipper/.git/hooks/post-checkout" ]; then
        echo "  ok  - first run installs symlink"
    else
        P_TESTS_FAILED=$((P_TESTS_FAILED + 1))
        echo "  FAIL - first run did not install symlink (rc=$rc1)"
    fi

    local target_before
    target_before=$(readlink "$tmp/klipper/.git/hooks/post-checkout")
    HOME="$tmp" SUDO_USER="" BASE_USER="" \
        bash "$tmp/THEOS-Configuration/scripts/enable-dev-hooks.sh" \
        >/dev/null 2>&1
    local rc2=$?
    local target_after
    target_after=$(readlink "$tmp/klipper/.git/hooks/post-checkout")
    P_TESTS_RUN=$((P_TESTS_RUN + 1))
    if [ "$rc2" -eq 0 ] && [ "$target_before" = "$target_after" ]; then
        echo "  ok  - second run is a no-op"
    else
        P_TESTS_FAILED=$((P_TESTS_FAILED + 1))
        echo "  FAIL - second run changed state (rc=$rc2, before=$target_before, after=$target_after)"
    fi

    rm -rf "$tmp"
}

test_run_sh_removes_existing_hook() {
    echo "test_run_sh_removes_existing_hook:"
    local tmp; tmp=$(mktemp -d)
    mkdir -p "$tmp/klipper/.git/hooks"
    echo "stale-content" > "$tmp/klipper/.git/hooks/post-checkout"
    chmod +x "$tmp/klipper/.git/hooks/post-checkout"

    HOME="$tmp" bash -c '
        HOOK_PATH=~/klipper/.git/hooks/post-checkout
        if [[ -e "$HOOK_PATH" || -L "$HOOK_PATH" ]]; then
            rm -f "$HOOK_PATH" || { echo "rm failed"; exit 1; }
        fi
        if [[ -e "$HOOK_PATH" || -L "$HOOK_PATH" ]]; then
            echo "still present"; exit 1
        fi
        exit 0
    '
    local rc=$?

    P_TESTS_RUN=$((P_TESTS_RUN + 1))
    if [ "$rc" -eq 0 ] && [ ! -e "$tmp/klipper/.git/hooks/post-checkout" ]; then
        echo "  ok  - run.sh preamble removed existing hook"
    else
        P_TESTS_FAILED=$((P_TESTS_FAILED + 1))
        echo "  FAIL - hook still present after run.sh preamble (rc=$rc)"
    fi
    rm -rf "$tmp"
}

test_post_checkout_filter() {
    echo "Starting post_checkout_filter tests..."
    test_branch_checkout_invokes_update
    test_file_checkout_skipped
    test_same_ref_skipped
    test_enable_dev_hooks_idempotent
    test_run_sh_removes_existing_hook
    echo
    echo "post_checkout_filter tests: $((P_TESTS_RUN - P_TESTS_FAILED))/$P_TESTS_RUN passed"
    [ "$P_TESTS_FAILED" -eq 0 ]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_post_checkout_filter
fi
