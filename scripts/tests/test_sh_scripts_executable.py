#!/usr/bin/env python3
"""Tests that every shell script under scripts/ is tracked with the
executable bit set in git (mode 100755).

When .sh files are tracked as 100644, the installer's
`find . -name '*.sh' -exec chmod +x {}` step flips the on-disk mode
to 100755. With core.fileMode=true (git's default) this turns the
working tree dirty: moonraker's update-manager then reports the repo
as 'dirty' and refuses updates.

Fix is one-off: `git update-index --chmod=+x <file>` on each script,
then commit. The test pins the contract so a future contributor who
adds a new .sh file with non-executable mode notices before push.
"""

import os
import subprocess
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))


class ShScriptsExecutableTest(unittest.TestCase):
    def test_every_tracked_sh_script_is_executable_in_index(self):
        out = subprocess.check_output(
            ["git", "ls-files", "--stage"],
            cwd=REPO_ROOT,
            text=True,
        )
        offenders = []
        for line in out.splitlines():
            parts = line.split(None, 3)
            if len(parts) < 4:
                continue
            mode, _sha, _stage, path = parts
            if not path.startswith("scripts/"):
                continue
            if not path.endswith(".sh"):
                continue
            if mode != "100755":
                offenders.append((mode, path))
        self.assertEqual(
            offenders,
            [],
            msg=(
                "{} .sh files are tracked non-executable (mode 100644). "
                "Run `git update-index --chmod=+x <file>` and commit:\n  "
                + "\n  ".join("{} {}".format(m, p) for m, p in offenders)
            ).format(len(offenders)),
        )


if __name__ == "__main__":
    unittest.main()
