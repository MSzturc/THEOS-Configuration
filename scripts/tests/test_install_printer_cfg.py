#!/usr/bin/env python3
"""Tests for the wizard-mode bootstrap behaviour of install-printer-cfg.sh."""
import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
INSTALLER = os.path.join(REPO_ROOT, "scripts", "install-printer-cfg.sh")


class InstallPrinterCfgTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.home, "printer_data", "config"))

    def tearDown(self):
        shutil.rmtree(self.home)

    def _run(self):
        env = dict(os.environ, HOME=self.home, USER="pi")
        return subprocess.run(["bash", INSTALLER], env=env,
                              capture_output=True, text=True)

    def _printer_cfg(self):
        return os.path.join(self.home, "printer_data", "config",
                            "printer.cfg")

    def test_writes_bootstrap_when_absent(self):
        r = self._run()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.isfile(self._printer_cfg()))
        with open(self._printer_cfg()) as f:
            body = f.read()
        self.assertIn("[setup_wizard]", body)
        self.assertIn("/tmp/klipper_host_mcu", body)

    def test_keeps_existing(self):
        with open(self._printer_cfg(), "w") as f:
            f.write("[mcu]\nserial: /dev/real\n")
        r = self._run()
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(self._printer_cfg()) as f:
            self.assertIn("/dev/real", f.read())


if __name__ == "__main__":
    unittest.main()
