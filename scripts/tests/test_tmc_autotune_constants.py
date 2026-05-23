#!/usr/bin/env python3
"""tuning_goal + autotune constants render correctly for the automatic configs."""
import os, sys, shutil, tempfile, textwrap, unittest, configparser

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
WORKSPACE_ROOT = os.path.abspath(os.path.join(REPO_ROOT, ".."))
KLIPPY_DIR = os.path.join(WORKSPACE_ROOT, "klipper", "klippy")
sys.path.insert(0, KLIPPY_DIR)
import configfile  # noqa: E402

REQUIRED = "xy_run_current: 1.768\nxy_motor: ldo-42sth48-2504ac\nxy_voltage: 56\n"


class TmcAutotuneConstantsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        dst = os.path.join(self.tmp, "config", "steppers", "automatic")
        shutil.copytree(
            os.path.join(REPO_ROOT, "config", "steppers", "automatic"), dst)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def _load(self, tmc, leaf, body=""):
        cfg = textwrap.dedent("""\
            [constants]
            {req}{body}

            [include config/steppers/automatic/{tmc}/{leaf}]
        """).format(req=REQUIRED, body=body, tmc=tmc, leaf=leaf)
        path = os.path.join(self.tmp, "printer.cfg")
        with open(path, "w") as f:
            f.write(cfg)
        reader = configfile.ConfigFileReader()
        data = reader.read_config_file(path)
        return reader.build_fileconfig_with_includes(data, path)

    def test_5160_default_tuning_goal_balanced(self):
        fc = self._load("5160", "2wd.cfg")
        self.assertEqual(fc.get("tmc5160 stepper_x", "tuning_goal"), "balanced")

    def test_5160_tuning_goal_override(self):
        fc = self._load("5160", "2wd.cfg", "xy_tuning_goal: silent\n")
        self.assertEqual(fc.get("tmc5160 stepper_x", "tuning_goal"), "silent")

    def test_5160_conflict_defaults_absent(self):
        fc = self._load("5160", "2wd.cfg")
        # chopper_freq_target / stealthchop_threshold must NOT be hard-set:
        # with no override they resolve to :None and are removed by the parser.
        self.assertFalse(fc.has_option("tmc5160 stepper_x",
                                       "chopper_freq_target"))
        self.assertFalse(fc.has_option("tmc5160 stepper_x",
                                       "stealthchop_threshold"))

    def test_5160_chopper_freq_override(self):
        fc = self._load("5160", "2wd.cfg", "xy_chopper_freq_target: 30000\n")
        self.assertEqual(
            float(fc.get("tmc5160 stepper_x", "chopper_freq_target")), 30000.)

    def test_2209_default_tuning_goal_balanced(self):
        fc = self._load("2209", "2wd.cfg")
        self.assertEqual(fc.get("tmc2209 stepper_x", "tuning_goal"), "balanced")

    def test_2209_tuning_goal_override(self):
        fc = self._load("2209", "2wd.cfg", "xy_tuning_goal: performance\n")
        self.assertEqual(
            fc.get("tmc2209 stepper_x", "tuning_goal"), "performance")

    def test_2209_omits_unsupported_fields(self):
        fc = self._load("2209", "2wd.cfg")
        for opt in ("driver_tpfd", "driver_cs", "high_velocity_threshold"):
            self.assertFalse(
                fc.has_option("tmc2209 stepper_x", opt),
                msg="2209 config must not set %s" % opt)

    def test_2209_4wd_has_four_steppers(self):
        fc = self._load("2209", "4wd.cfg")
        for s in ("stepper_x", "stepper_y", "stepper_x1", "stepper_y1"):
            self.assertTrue(fc.has_section("tmc2209 %s" % s))

    def test_2209_extruder_coolstep_threshold_override(self):
        body = ("e_run_current: 1.0\ne_motor: ldo-36sth20-1004ahg\n"
                "e_voltage: 24\ne_coolstep_threshold: 50\n")
        fc = self._load("2209", "extruder.cfg", body)
        self.assertEqual(
            float(fc.get("tmc2209 extruder", "coolstep_threshold")), 50.)


if __name__ == "__main__":
    unittest.main()
