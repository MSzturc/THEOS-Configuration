#!/usr/bin/env python3
"""Each cooling fan ships its own speed-shortcut macro, co-located with the
fan it drives: include the fan leaf and you get the shortcut for free. SFS
travels with the CPAP part-cooling fan; SBS travels with the side blowers and
binds to whichever fan that leaf defines (plural for the dual duct, singular
for the single one)."""

import os
import sys
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
WORKSPACE_ROOT = os.path.abspath(os.path.join(REPO_ROOT, ".."))
KLIPPY_DIR = os.path.join(WORKSPACE_ROOT, "klipper", "klippy")

sys.path.insert(0, KLIPPY_DIR)
import configfile  # noqa: E402


def load_fan(name):
    path = os.path.join(REPO_ROOT, "config", "fans", name)
    reader = configfile.ConfigFileReader()
    data = reader.read_config_file(path)
    return reader.build_fileconfig_with_includes(data, path)


class FanShortcutMacroTest(unittest.TestCase):
    def test_cpap_fan_carries_sfs(self):
        fc = load_fan("part_fan_cpap.cfg")
        self.assertTrue(fc.has_section("gcode_macro SFS"))
        self.assertIn("FAN=CPAP", fc.get("gcode_macro SFS", "gcode"))

    def test_dual_side_blower_carries_sbs(self):
        fc = load_fan("side_blower_fan_dual.cfg")
        self.assertTrue(fc.has_section("gcode_macro SBS"))
        self.assertIn("FAN=Side_Blowers", fc.get("gcode_macro SBS", "gcode"))

    def test_single_side_blower_carries_sbs(self):
        fc = load_fan("side_blower_fan_single.cfg")
        self.assertTrue(fc.has_section("gcode_macro SBS"))
        # The single variant binds the shortcut to its own (singular) fan name.
        gcode = fc.get("gcode_macro SBS", "gcode")
        self.assertIn("FAN=Side_Blower ", gcode)
        self.assertNotIn("Side_Blowers", gcode)


if __name__ == "__main__":
    unittest.main()
