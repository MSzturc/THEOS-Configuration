#!/usr/bin/env python3
"""Tests that every hotend cfg ships a default heater control algorithm.

Klipper's [extruder] section requires `control` (pid or watermark). On a
fresh install the SAVE_CONFIG block in printer.cfg is empty, so the only
remaining source for `control` is the hotend cfg. Without it, klippy
refuses to start with:

    configparser.Error: Option 'control' in section 'extruder' must be
    specified

So each hotend file must provide a placeholder `control: pid` plus
pid_Kp/pid_Ki/pid_Kd defaults. The user replaces them by running
PID_CALIBRATE EXTRUDER TARGET=<temp> + SAVE_CONFIG.
"""

import os
import shutil
import sys
import tempfile
import textwrap
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
WORKSPACE_ROOT = os.path.abspath(os.path.join(REPO_ROOT, ".."))
KLIPPY_DIR = os.path.join(WORKSPACE_ROOT, "klipper", "klippy")

sys.path.insert(0, KLIPPY_DIR)
import configfile  # noqa: E402


HOTENDS = [
    "chc-pro.cfg",
    "goliath.cfg",
    "mosquito-magnum.cfg",
    "rapido-uhf.cfg",
    "std6-v2.cfg",
]
WIRING_INCLUDES = ["default_wiring.cfg", "dual_wiring.cfg"]


class HotendControlDefaultTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        hotends_dir = os.path.join(self.tmp, "config", "hotends")
        os.makedirs(hotends_dir)
        for name in HOTENDS + WIRING_INCLUDES:
            shutil.copy(
                os.path.join(REPO_ROOT, "config", "hotends", name),
                os.path.join(hotends_dir, name),
            )

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def _load(self, hotend):
        cfg = textwrap.dedent("""\
            [include config/hotends/{hotend}]
        """).format(hotend=hotend)
        path = os.path.join(self.tmp, "printer.cfg")
        with open(path, "w") as f:
            f.write(cfg)
        reader = configfile.ConfigFileReader()
        data = reader.read_config_file(path)
        return reader.build_fileconfig_with_includes(data, path)

    def test_each_hotend_specifies_control_pid(self):
        for hotend in HOTENDS:
            with self.subTest(hotend=hotend):
                fc = self._load(hotend)
                self.assertTrue(fc.has_section("extruder"))
                self.assertTrue(
                    fc.has_option("extruder", "control"),
                    msg="{} missing 'control' option".format(hotend),
                )
                self.assertEqual(
                    fc.get("extruder", "control").strip(),
                    "pid",
                    msg="{} 'control' is not 'pid'".format(hotend),
                )

    def test_each_hotend_provides_pid_defaults(self):
        for hotend in HOTENDS:
            with self.subTest(hotend=hotend):
                fc = self._load(hotend)
                for opt in ("pid_Kp", "pid_Ki", "pid_Kd"):
                    self.assertTrue(
                        fc.has_option("extruder", opt),
                        msg="{} missing {}".format(hotend, opt),
                    )
                    val = float(fc.get("extruder", opt))
                    self.assertGreater(
                        val,
                        0.0,
                        msg="{} {} must be > 0".format(hotend, opt),
                    )


if __name__ == "__main__":
    unittest.main()
