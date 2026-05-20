#!/usr/bin/env python3
"""Tests for scripts/helpers/version.sh — parse_klipper_version and
read_mcu_version_from_log. Bash functions are exercised through a small
shim that sources the helper and prints the output."""

import os
import subprocess
import tempfile
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HELPERS_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "helpers"))
HELPER = os.path.join(HELPERS_DIR, "version.sh")


def _bash(cmd):
    """Run a bash one-liner with version.sh sourced, return (rc, stdout)."""
    full = "set -e; source '{0}'; {1}".format(HELPER, cmd)
    proc = subprocess.run(
        ["bash", "-c", full], capture_output=True, text=True
    )
    return proc.returncode, proc.stdout.strip()


class ParseKlipperVersionTest(unittest.TestCase):

    def _parse(self, version):
        return _bash(
            "parse_klipper_version '{v}' && "
            "echo \"major=$major minor=$minor patch=$patch\"".format(v=version)
        )

    def test_plain_release_tag(self):
        rc, out = self._parse("v0.13.0")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "major=0 minor=13 patch=0")

    def test_tag_with_commits_and_sha(self):
        rc, out = self._parse("v0.13.0-650-g6fa08beb7")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "major=0 minor=13 patch=0")

    def test_tag_with_patch_increment(self):
        rc, out = self._parse("v0.13.1-5-gabcdef12")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "major=0 minor=13 patch=1")

    def test_dirty_suffix(self):
        rc, out = self._parse("v0.13.1-5-gabcdef12-dirty")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "major=0 minor=13 patch=1")

    def test_dirty_with_timestamp_and_hostname(self):
        rc, out = self._parse(
            "v0.13.0-650-g6fa08beb7-dirty-20260520_103045-myhost")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "major=0 minor=13 patch=0")

    def test_two_digit_minor(self):
        rc, out = self._parse("v0.14.2-100-gXXXXXXXX")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "major=0 minor=14 patch=2")

    def test_empty_string_fails(self):
        rc, _ = self._parse("")
        self.assertNotEqual(rc, 0)

    def test_sha_only_fails(self):
        rc, _ = self._parse("6fa08beb7")
        self.assertNotEqual(rc, 0)

    def test_garbage_fails(self):
        rc, _ = self._parse("garbage")
        self.assertNotEqual(rc, 0)


class ReadMcuVersionFromLogTest(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.log = os.path.join(self.tmp, "klippy.log")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp)

    def _run(self):
        return _bash(
            "read_mcu_version_from_log '{p}'".format(p=self.log)
        )

    def test_missing_log_returns_empty(self):
        rc, out = self._run()
        self.assertEqual(rc, 0)
        self.assertEqual(out, "")

    def test_empty_log_returns_empty(self):
        with open(self.log, "w"):
            pass
        rc, out = self._run()
        self.assertEqual(rc, 0)
        self.assertEqual(out, "")

    def test_single_loaded_mcu_line(self):
        with open(self.log, "w") as f:
            f.write("some boot noise\n")
            f.write("Loaded MCU 'mcu' 167 commands "
                    "(v0.13.0-650-g6fa08beb7 / gcc: 11.3)\n")
        rc, out = self._run()
        self.assertEqual(rc, 0)
        self.assertEqual(out, "v0.13.0-650-g6fa08beb7")

    def test_last_of_many_wins(self):
        with open(self.log, "w") as f:
            f.write("Loaded MCU 'mcu' 167 commands "
                    "(v0.13.0-100-gAAAAAAA / gcc: 11.3)\n")
            f.write("Loaded MCU 'mcu' 167 commands "
                    "(v0.13.0-200-gBBBBBBB / gcc: 11.3)\n")
            f.write("Loaded MCU 'mcu' 167 commands "
                    "(v0.13.1-5-gCCCCCCC / gcc: 11.3)\n")
        rc, out = self._run()
        self.assertEqual(rc, 0)
        self.assertEqual(out, "v0.13.1-5-gCCCCCCC")

    def test_secondary_mcu_ignored(self):
        with open(self.log, "w") as f:
            f.write("Loaded MCU 'mcu' 167 commands "
                    "(v0.13.0-650-gPRIMARY / gcc: 11.3)\n")
            f.write("Loaded MCU 'adxl' 80 commands "
                    "(v0.13.0-999-gWRONG / gcc: 11.3)\n")
        rc, out = self._run()
        self.assertEqual(rc, 0)
        self.assertEqual(out, "v0.13.0-650-gPRIMARY")

    def test_dirty_version_in_log(self):
        with open(self.log, "w") as f:
            f.write("Loaded MCU 'mcu' 167 commands "
                    "(v0.13.0-650-g6fa08beb7-dirty-20260520_103045-myhost"
                    " / gcc: 11.3)\n")
        rc, out = self._run()
        self.assertEqual(rc, 0)
        self.assertEqual(
            out,
            "v0.13.0-650-g6fa08beb7-dirty-20260520_103045-myhost",
        )


if __name__ == "__main__":
    unittest.main()
