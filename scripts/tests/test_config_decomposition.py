#!/usr/bin/env python3
"""Tests for the THEOS-Configuration 2.0 decomposition.

Loads the new meta-definitions through the enhanced Klipper config parser
and verifies that each pulls in its expected leaf sections, sets its label,
and that a wizard-style reference assembly reproduces the legacy monolith's
safety-critical derived values (the t250 bed_mesh box).
"""

import os
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


def load(path):
    reader = configfile.ConfigFileReader()
    data = reader.read_config_file(path)
    return reader.build_fileconfig_with_includes(data, path)


def load_module(*relparts):
    return load(os.path.join(REPO_ROOT, "config", *relparts))


class ToolheadMetaTest(unittest.TestCase):
    def test_dualhorn(self):
        fc = load_module("toolheads", "dualhorn", "toolhead.cfg")
        self.assertEqual(fc.get("constants", "toolhead_label"), "DualHorn")
        # nozzle/filament domain constants live on the toolhead; e_motor lives
        # in the printer meta with the driver tuning.
        self.assertEqual(fc.get("constants", "nozzle_diameter"), "0.5")
        self.assertEqual(fc.get("constants", "filament_diameter"), "1.75")
        # Extruder kinematics from extruders/t250-bmg.cfg
        self.assertTrue(fc.has_section("extruder"))
        self.assertEqual(fc.get("extruder", "gear_ratio"), "50:10")
        # firmware_retraction ships with the t250 extruder leaf
        self.assertTrue(fc.has_section("firmware_retraction"))
        # The hotend is its own wizard dimension -- the toolhead must not pull
        # one (no thermistor/heater on the mount itself).
        self.assertFalse(fc.has_option("extruder", "sensor_type"))

    def test_scorpio(self):
        fc = load_module("toolheads", "scorpio", "toolhead.cfg")
        self.assertEqual(fc.get("constants", "toolhead_label"), "Scorpio")
        self.assertEqual(fc.get("constants", "nozzle_diameter"), "0.5")
        # Scorpio carries the t250-vzg extruder (gear 60:10); the hotend is
        # selected separately, so no thermistor here.
        self.assertTrue(fc.has_section("extruder"))
        self.assertEqual(fc.get("extruder", "gear_ratio"), "60:10")
        self.assertFalse(fc.has_option("extruder", "sensor_type"))

    def test_standard(self):
        fc = load_module("toolheads", "standard", "toolhead.cfg")
        self.assertEqual(fc.get("constants", "toolhead_label"), "Standard")
        self.assertTrue(fc.has_section("extruder"))
        self.assertFalse(fc.has_option("extruder", "sensor_type"))

    def test_compatible_printers(self):
        # Toolhead mounts are printer-specific; the wizard filters on this.
        self.assertEqual(
            load_module("toolheads", "dualhorn",
                        "toolhead.cfg").get("constants",
                                            "compatible_printers"), "t250")
        self.assertEqual(
            load_module("toolheads", "scorpio",
                        "toolhead.cfg").get("constants",
                                            "compatible_printers"), "t250")
        self.assertEqual(
            load_module("toolheads", "standard",
                        "toolhead.cfg").get("constants",
                                            "compatible_printers"), "t100")


class HotendMetaTest(unittest.TestCase):
    def test_label_and_extruder(self):
        fc = load_module("hotends", "rapido-uhf", "hotend.cfg")
        self.assertEqual(fc.get("constants", "hotend_label"), "Rapido UHF")
        self.assertTrue(fc.has_section("extruder"))
        self.assertEqual(fc.get("extruder", "sensor_type"),
                         "ATC Semitec 104NT-4-R025H42G")

    def test_single_heater_hotend_uses_default_wiring(self):
        # default_wiring resolves heater_pin to the single E_HEATER alias.
        fc = load_module("hotends", "chc-pro", "hotend.cfg")
        self.assertEqual(fc.get("extruder", "heater_pin"), "E_HEATER")
        self.assertFalse(fc.has_section("multi_pin dual_heater"))

    def test_dual_heater_hotend_uses_dual_wiring(self):
        # STD6 V2 needs two cartridges -- dual_wiring rewires heater_pin onto
        # the [multi_pin dual_heater] group (E_HEATER + E1_HEATER).
        fc = load_module("hotends", "std6-v2", "hotend.cfg")
        self.assertEqual(fc.get("extruder", "heater_pin"),
                         "multi_pin:dual_heater")
        self.assertTrue(fc.has_section("multi_pin dual_heater"))
        self.assertEqual(fc.get("multi_pin dual_heater", "pins"),
                         "E_HEATER, E1_HEATER")

    def test_all_hotends_carry_a_label(self):
        import glob
        base = os.path.join(REPO_ROOT, "config", "hotends")
        metas = sorted(glob.glob(os.path.join(base, "*", "hotend.cfg")))
        self.assertGreaterEqual(len(metas), 5)
        for meta in metas:
            fc = load(meta)
            self.assertTrue(fc.get("constants", "hotend_label").strip(), meta)


class BedMetaTest(unittest.TestCase):
    def _read(self, *relparts):
        with open(os.path.join(REPO_ROOT, "config", *relparts)) as f:
            return f.read()

    def test_ender3_bed(self):
        body = self._read("beds", "ender-3", "bed.cfg")
        self.assertIn("bed_label: Ender 3", body)
        self.assertIn("compatible_printers: t250", body)
        for needle in ("../dynamic_size.cfg", "../dynamic_mesh.cfg",
                       "config.cfg", "z-tilt-leveling-t250.cfg",
                       "../twist-compensation.cfg", "screw-tilt-t250.cfg"):
            self.assertIn(needle, body, needle)

    def test_ender2pro_bed(self):
        body = self._read("beds", "ender-2-pro", "bed.cfg")
        self.assertIn("bed_label: Ender 2 Pro", body)
        self.assertIn("compatible_printers: t100", body)
        for needle in ("size.cfg", "config.cfg",
                       "manual-leveling-t100.cfg", "mesh-t100.cfg"):
            self.assertIn(needle, body, needle)


class PrinterMetaTest(unittest.TestCase):
    def test_t250_frame(self):
        fc = load_module("printers", "t250", "printer.cfg")
        self.assertEqual(fc.get("constants", "printer_label"), "T250")
        self.assertEqual(fc.get("constants", "has_toolheadboard"), "false")
        # Printer carries its frame/probe constants AND the extruder motor
        # constants (consumed by the 5160 extruder driver tuning it includes).
        self.assertEqual(fc.get("constants", "print_volume_x"), "192")
        self.assertEqual(fc.get("constants", "probe_offset_x"), "1.875")
        self.assertEqual(fc.get("constants", "e_motor"), "moons-cse14hra1l410a")
        self.assertEqual(fc.get("printer", "kinematics"), "corexy")
        # AWD adds the second X/Y motion steppers
        self.assertTrue(fc.has_section("stepper_x1"))
        self.assertTrue(fc.has_section("stepper_y1"))
        # Stock BDsensor probe + stock input shaper are part of the printer meta
        self.assertTrue(fc.has_section("BDsensor"))
        self.assertTrue(fc.has_section("input_shaper"))

    def test_t100_frame(self):
        fc = load_module("printers", "t100", "printer.cfg")
        self.assertEqual(fc.get("constants", "printer_label"), "T100")
        self.assertEqual(fc.get("constants", "has_toolheadboard"), "false")
        self.assertEqual(fc.get("printer", "kinematics"), "corexy")
        self.assertTrue(fc.has_section("stepper_x"))
        # Stock sensorless override is functionally required (default would be
        # 255 = axes won't move).
        self.assertEqual(fc.get("tmc2209 stepper_x", "driver_SGTHRS"), "90")


class AccessoryTest(unittest.TestCase):
    def test_fysetc_pis_accessory(self):
        fc = load_module("accessories", "fysetc-pis", "accessory.cfg")
        self.assertEqual(fc.get("constants", "accessory_label"),
                         "FYSETC Portable Input Shaper")
        self.assertTrue(fc.has_section("adxl345"))
        self.assertTrue(fc.has_section("resonance_tester"))
        self.assertTrue(fc.has_section("shaketune"))

    def test_fysetc_nis_accessory(self):
        fc = load_module("accessories", "fysetc-nis", "accessory.cfg")
        self.assertEqual(fc.get("constants", "accessory_label"),
                         "FYSETC Nozzle Input Shaper")
        self.assertTrue(fc.has_section("adxl345"))
        self.assertTrue(fc.has_section("resonance_tester"))
        self.assertTrue(fc.has_section("shaketune"))


class DefaultShaketuneTest(unittest.TestCase):
    def _read(self, *relparts):
        with open(os.path.join(REPO_ROOT, "config", *relparts)) as f:
            return f.read()

    def test_shaketune_lives_in_default_leaf(self):
        self.assertIn("[shaketune]",
                      self._read("accessories", "default_shaketune.cfg"))

    def test_both_accel_accessories_pull_it(self):
        for acc in ("fysetc-nis", "fysetc-pis"):
            body = self._read("accessories", acc, "%s.cfg" % acc)
            self.assertIn("../default_shaketune.cfg", body, acc)


class BootstrapTest(unittest.TestCase):
    def test_bootstrap_supplies_printer_limits(self):
        # kinematics:none still requires max_velocity/max_accel, so the
        # wizard-mode bootstrap must carry them or klippy halts on first boot.
        fc = load_module("bootstrap", "wizard.cfg")
        self.assertEqual(fc.get("printer", "kinematics"), "none")
        self.assertGreater(fc.getfloat("printer", "max_velocity"), 0)
        self.assertGreater(fc.getfloat("printer", "max_accel"), 0)


class BaseEssentialsTest(unittest.TestCase):
    def test_essentials_contents(self):
        # essentials.cfg cannot parse standalone — its macros reference printer
        # constants (e.g. macros/print.cfg uses ${constants.print_volume_y}
        # without a default, and the fork parser raises on undefined refs).
        # Parse-correctness within a real config is covered by the t250/t100
        # generator render->validate tests; here we assert the base layer wires
        # the expected pieces at the text level.
        with open(os.path.join(REPO_ROOT, "config", "base",
                               "essentials.cfg")) as f:
            body = f.read()
        self.assertNotIn("[shaketune]", body)
        self.assertIn("../../mainsail.cfg", body)
        self.assertIn("[pa_test]", body)
        self.assertIn("../../macros/print.cfg", body)
        self.assertIn("../../macros/helpers/CG28.cfg", body)


class ReferenceAssemblyTest(unittest.TestCase):
    def _parse_pair(self, value):
        x, y = value.split(",")
        return float(x.strip()), float(y.strip())

    def _assemble(self, printer, toolhead, bed):
        # Compose like the wizard will: printer + toolhead + bed + board, with
        # ONLY a minimal printer-id seed. Domain constants come from meta-defs.
        body = textwrap.dedent("""\
            [constants]
            printer: {printer}

            [include {root}/config/printers/{printer}/printer.cfg]
            [include {root}/config/toolheads/{toolhead}/toolhead.cfg]
            [include {root}/config/beds/{bed}/bed.cfg]
            [include {root}/config/boards/{board}/config.cfg]
        """).format(printer=printer, toolhead=toolhead, bed=bed,
                    board=("btt-kraken" if printer == "t250"
                           else "btt-skr-pico"),
                    root=REPO_ROOT.replace("\\", "/"))
        tmp = tempfile.NamedTemporaryFile(
            mode="w", suffix=".cfg", delete=False, dir=REPO_ROOT)
        tmp.write(body); tmp.close()
        try:
            return load(tmp.name)
        finally:
            os.unlink(tmp.name)

    def test_t250_assembly_matches_legacy(self):
        fc = self._assemble("t250", "dualhorn", "ender-3")
        mn = self._parse_pair(fc.get("bed_mesh", "mesh_min"))
        mx = self._parse_pair(fc.get("bed_mesh", "mesh_max"))
        self.assertAlmostEqual(mn[0], 16.875, places=3)
        self.assertAlmostEqual(mn[1], 32.25, places=3)
        self.assertAlmostEqual(mx[0], 177.0, places=3)
        self.assertAlmostEqual(mx[1], 197.0, places=3)
        self.assertTrue(fc.has_section("extruder"))
        self.assertTrue(fc.has_section("tmc5160 stepper_x1"))
        self.assertTrue(fc.has_section("BDsensor"))

    def test_t100_assembly_parses(self):
        # t100 has no domain constants and no probe; it must still parse from
        # the meta-defs alone.
        fc = self._assemble("t100", "standard", "ender-2-pro")
        self.assertTrue(fc.has_section("stepper_x"))
        self.assertTrue(fc.has_section("extruder"))


if __name__ == "__main__":
    unittest.main()
