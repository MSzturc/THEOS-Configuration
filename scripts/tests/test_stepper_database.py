#!/usr/bin/env python3
"""The stepper-driver reference libraries live in THEOS-Configuration as data:
motor specs (motor_constants) and stepstick carrier specs. They are included
via the base layer; the Klipper fork keeps only the parsing logic."""

import os
import sys
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
WORKSPACE_ROOT = os.path.abspath(os.path.join(REPO_ROOT, ".."))
KLIPPY_DIR = os.path.join(WORKSPACE_ROOT, "klipper", "klippy")

sys.path.insert(0, KLIPPY_DIR)
import configfile  # noqa: E402

DB = os.path.join(REPO_ROOT, "config", "steppers", "database")


def load(path):
    reader = configfile.ConfigFileReader()
    data = reader.read_config_file(path)
    return reader.build_fileconfig_with_includes(data, path)


class MotorDatabaseTest(unittest.TestCase):
    def test_known_motors_present(self):
        fc = load(os.path.join(DB, "motors.cfg"))
        # The T250 stock extruder motor and a Siboor variant used in the field.
        self.assertTrue(fc.has_section("motor_constants moons-cse14hra1l410a"))
        self.assertTrue(fc.has_section("motor_constants siboor-14sth20-1004a"))
        # A motor that exists only in the THEOS database, not upstream.
        self.assertTrue(fc.has_section(
            "motor_constants ldo-42sth48-2804ah-custom"))

    def test_motor_spec_fields_present(self):
        fc = load(os.path.join(DB, "motors.cfg"))
        sec = "motor_constants moons-cse14hra1l410a"
        for field in ("resistance", "inductance", "holding_torque",
                      "steps_per_revolution", "max_current"):
            self.assertTrue(fc.has_option(sec, field), field)

    def test_full_database_present(self):
        # The newest upstream database ships 201 [motor_constants] plus 27
        # [motor_alias] redirects; the aliases are flattened into full
        # [motor_constants] here (see test_no_motor_alias_sections), and one
        # THEOS-only motor is kept on top: 201 + 27 + 1 = 229.
        fc = load(os.path.join(DB, "motors.cfg"))
        motors = [s for s in fc.sections()
                  if s.startswith("motor_constants ")]
        self.assertEqual(len(motors), 229)

    def test_no_motor_alias_sections(self):
        # The Klipper fork has no motor_alias handler; an unhandled
        # [motor_alias ...] section aborts startup ("not a valid config
        # section"). Upstream aliases must therefore be flattened, not shipped.
        with open(os.path.join(DB, "motors.cfg")) as f:
            self.assertNotIn("[motor_alias", f.read())

    def test_flattened_alias_carries_target_spec(self):
        # qidi-BJ42D29-28V07 was an upstream alias for qidi-bj42d29-28v07;
        # after flattening it must carry the target's specs verbatim.
        fc = load(os.path.join(DB, "motors.cfg"))
        alias, target = ("motor_constants qidi-BJ42D29-28V07",
                         "motor_constants qidi-bj42d29-28v07")
        for field in ("resistance", "inductance", "holding_torque",
                      "max_current", "steps_per_revolution"):
            self.assertEqual(fc.getfloat(alias, field),
                             fc.getfloat(target, field), field)

    def test_no_duplicate_motor_names(self):
        # The parser silently merges duplicate sections, so guard the raw file:
        # every motor name must appear exactly once.
        names = []
        with open(os.path.join(DB, "motors.cfg")) as f:
            for line in f:
                line = line.strip()
                if line.startswith("[motor_constants "):
                    names.append(line)
        self.assertEqual(sorted(names), sorted(set(names)))


class StepstickDatabaseTest(unittest.TestCase):
    def test_kraken_carriers(self):
        fc = load(os.path.join(DB, "stepsticks.cfg"))
        self.assertEqual(
            fc.getfloat("stepstick KRAKEN_2160_8A", "sense_resistor"), 0.022)
        self.assertEqual(
            fc.getfloat("stepstick KRAKEN_2160_8A", "max_current"), 8.0)
        self.assertEqual(
            fc.getfloat("stepstick KRAKEN_2160_3A", "sense_resistor"), 0.075)
        self.assertEqual(
            fc.getfloat("stepstick KRAKEN_2160_3A", "max_current"), 3.0)

    def test_all_twenty_carriers_present(self):
        fc = load(os.path.join(DB, "stepsticks.cfg"))
        carriers = [s for s in fc.sections() if s.startswith("stepstick ")]
        self.assertEqual(len(carriers), 20)


class EssentialsIncludesDatabaseTest(unittest.TestCase):
    def test_base_layer_includes_both_databases(self):
        with open(os.path.join(REPO_ROOT, "config", "base",
                               "essentials.cfg")) as f:
            body = f.read()
        self.assertIn("steppers/database/motors.cfg", body)
        self.assertIn("steppers/database/stepsticks.cfg", body)


if __name__ == "__main__":
    unittest.main()
