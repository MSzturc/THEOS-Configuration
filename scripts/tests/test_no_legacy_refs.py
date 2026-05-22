#!/usr/bin/env python3
"""Guard: no config/script references the removed legacy files."""
import os
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
NEEDLES = ["base.cfg", "templates/", "printers/t250.cfg",
           "printers/t100.cfg", "boards/fysetc-pis", "boards/fysetc-nis"]


class NoLegacyRefsTest(unittest.TestCase):
    def test_no_references(self):
        hits = []
        for root, _dirs, files in os.walk(REPO_ROOT):
            if ".git" in root.split(os.sep):
                continue
            for name in files:
                if not (name.endswith(".cfg") or name.endswith(".sh")):
                    continue
                p = os.path.join(root, name)
                with open(p, "r", errors="ignore") as f:
                    text = f.read()
                for needle in NEEDLES:
                    if needle in text:
                        hits.append("%s -> %s" % (p, needle))
        self.assertEqual(hits, [], "dangling legacy references:\n"
                         + "\n".join(hits))


if __name__ == "__main__":
    unittest.main()
