#!/bin/bash

TEST_DIR="./tests"

if [[ -d "$TEST_DIR" ]]; then
    for tests in "$TEST_DIR"/*.sh; do
        if [[ -f "$tests" ]]; then
            source "$tests"
        fi
    done
else
    echo "Verzeichnis $TEST_DIR existiert nicht."
    exit 1
fi


# Call Tests
test_logs
test_parse_mcu
test_version
test_flash_auto_mode
test_flash_decision
test_post_checkout_filter
test_moonraker_branch
test_z_tilt_points
test_dynamic_mesh
test_twist_compensation
test_dual_wiring
test_nozzle_diameter
test_filament_diameter
test_primeline
test_print_pipeline
test_microsteps
test_tmc_interpolate
test_tmc_autotune_constants
test_second_homing_speed
test_safe_z_home
test_hotend_control_default
test_fan_shortcuts
test_stepper_database
test_decomposition
test_install_printer_cfg
test_no_legacy_refs
test_sh_scripts_executable
