#!/usr/bin/env python3
"""Tests for the maybe_flash_firmware() decision logic in update-klipper.sh.

Strategy: build a small fake environment under a tmpdir — a fake $HOME
containing klipper/.git, printer_data/config/printer.cfg,
printer_data/logs/klippy.log, and a THEOS-Configuration tree with the
real scripts. flash.sh, systemctl and git are stubbed by PATH-prepended
shims that record their invocations. We then source update-klipper.sh
and call maybe_flash_firmware directly, asserting that flash.sh was
(or wasn't) invoked."""

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))


class FlashDecisionTest(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(os.path.join(self.home, "klipper"))
        os.makedirs(os.path.join(self.home, "printer_data", "config"))
        os.makedirs(os.path.join(self.home, "printer_data", "logs"))
        # log.sh writes timestamp/log files under $(user_dir)/logs/
        os.makedirs(os.path.join(self.home, "logs"))
        self.cfg_root = os.path.join(self.home, "THEOS-Configuration")
        os.makedirs(os.path.join(self.cfg_root, "scripts", "helpers"))
        os.makedirs(os.path.join(self.cfg_root, "config", "boards",
                                 "btt-kraken"))
        for f in ["update-klipper.sh", "utils.sh", "flash.sh"]:
            shutil.copy(os.path.join(REPO_ROOT, "scripts", f),
                        os.path.join(self.cfg_root, "scripts", f))
        for f in ["log.sh", "user_dir.sh", "current_user.sh",
                  "parse_mcu.sh", "version.sh"]:
            shutil.copy(os.path.join(REPO_ROOT, "scripts", "helpers", f),
                        os.path.join(self.cfg_root, "scripts", "helpers", f))
        open(os.path.join(self.cfg_root, "config", "boards",
                          "btt-kraken", "firmware.config"), "w").close()
        with open(os.path.join(self.home, "printer_data", "config",
                               "printer.cfg"), "w") as f:
            f.write("[mcu]\nserial: /dev/btt-kraken\ncpu: stm32h723xx\n")
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        self._write_stub("systemctl", "exit 0")
        self._git_soll = "v0.13.0-650-gabc"
        self.flash_log = os.path.join(self.tmp, "flash.log")
        flash_stub = os.path.join(self.cfg_root, "scripts", "flash.sh")
        with open(flash_stub, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("echo \"flash.sh called args=$*\" >> '{0}'\n".format(
                self.flash_log))
            f.write("exit 0\n")
        os.chmod(flash_stub, 0o755)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def _write_stub(self, name, body):
        path = os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(body + "\n")
        os.chmod(path, 0o755)

    def _set_git_soll(self, version):
        self._git_soll = version
        self._write_stub(
            "git",
            'if [ "$1" = "-C" ] && [ "$3" = "describe" ]; then '
            'echo "{v}"; exit 0; fi; '
            'echo "git stub: unsupported $*" >&2; exit 1'.format(
                v=version),
        )

    def _set_log_ist(self, version_or_none):
        log = os.path.join(self.home, "printer_data", "logs", "klippy.log")
        if version_or_none is None:
            if os.path.exists(log):
                os.unlink(log)
            return
        with open(log, "w") as f:
            f.write("Loaded MCU 'mcu' 167 commands ("
                    + version_or_none + " / gcc: 11.3)\n")

    def _run_maybe_flash(self):
        env = os.environ.copy()
        env["HOME"] = self.home
        env["PATH"] = self.bin + os.pathsep + env["PATH"]
        script = textwrap.dedent("""\
            set -e
            export THEOS_LIBRARY_MODE=1
            source "{cfg}/scripts/update-klipper.sh"
            maybe_flash_firmware
        """).format(cfg=self.cfg_root)
        proc = subprocess.run(["bash", "-c", script], env=env,
                              capture_output=True, text=True)
        return proc.returncode, proc.stdout, proc.stderr

    def _flash_called(self):
        return (os.path.exists(self.flash_log)
                and os.path.getsize(self.flash_log) > 0)

    def test_same_patch_no_flash(self):
        self._set_git_soll("v0.13.0-650-gAAA")
        self._set_log_ist("v0.13.0-100-gBBB")
        rc, _, _ = self._run_maybe_flash()
        self.assertEqual(rc, 0)
        self.assertFalse(self._flash_called())

    def test_different_patch_flashes(self):
        self._set_git_soll("v0.13.1-5-gAAA")
        self._set_log_ist("v0.13.0-650-gBBB")
        rc, _, _ = self._run_maybe_flash()
        self.assertEqual(rc, 0)
        self.assertTrue(self._flash_called())

    def test_different_minor_flashes(self):
        self._set_git_soll("v0.14.0-1-gAAA")
        self._set_log_ist("v0.13.5-7-gBBB")
        rc, _, _ = self._run_maybe_flash()
        self.assertEqual(rc, 0)
        self.assertTrue(self._flash_called())

    def test_downgrade_flashes(self):
        self._set_git_soll("v0.13.1-5-gAAA")
        self._set_log_ist("v0.14.0-1-gBBB")
        rc, _, _ = self._run_maybe_flash()
        self.assertEqual(rc, 0)
        self.assertTrue(self._flash_called())

    def test_dirty_suffix_ignored(self):
        self._set_git_soll("v0.13.0-650-gAAA")
        self._set_log_ist(
            "v0.13.0-650-gAAA-dirty-20260520_103045-myhost")
        rc, _, _ = self._run_maybe_flash()
        self.assertEqual(rc, 0)
        self.assertFalse(self._flash_called())

    def test_log_missing_flashes_as_fallback(self):
        self._set_git_soll("v0.13.0-650-gAAA")
        self._set_log_ist(None)
        rc, _, _ = self._run_maybe_flash()
        self.assertEqual(rc, 0)
        self.assertTrue(self._flash_called())

    def test_git_sha_only_flashes_as_fallback(self):
        self._set_git_soll("6fa08beb7")
        self._set_log_ist("v0.13.0-650-gBBB")
        rc, _, _ = self._run_maybe_flash()
        self.assertEqual(rc, 0)
        self.assertTrue(self._flash_called())

    def test_missing_firmware_config_skips(self):
        os.unlink(os.path.join(
            self.cfg_root, "config", "boards", "btt-kraken",
            "firmware.config"))
        self._set_git_soll("v0.13.1-5-gAAA")
        self._set_log_ist("v0.13.0-650-gBBB")
        rc, _, _ = self._run_maybe_flash()
        self.assertEqual(rc, 0)
        self.assertFalse(self._flash_called())


if __name__ == "__main__":
    unittest.main()
