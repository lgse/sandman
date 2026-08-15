import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "sandman.py"


class SandmanHelperTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        base = Path(self.temporary.name)
        self.shell = base / "shell.json"
        self.config = base / "sandman.json"
        self.shell.write_text(
            json.dumps({"version": 1, "idle": {"screensaver": 150, "lock": 300}, "unrelated": True}),
            encoding="utf-8",
        )
        self.environment = {
            **os.environ,
            "OMARCHY_SHELL_CONFIG_PATH": str(self.shell),
            "SANDMAN_CONFIG_PATH": str(self.config),
        }

    def tearDown(self):
        self.temporary.cleanup()

    def run_helper(self, *arguments):
        completed = subprocess.run(
            ["python3", str(HELPER), *arguments],
            env=self.environment,
            check=True,
            text=True,
            capture_output=True,
        )
        return json.loads(completed.stdout)

    def test_init_inherits_omarchy_screensaver_and_disables_sleep(self):
        expected = {"screensaver": 150, "sleep": 0, "lockDelay": 150}
        self.assertEqual(self.run_helper("init"), expected)
        self.assertEqual(json.loads(self.config.read_text()), expected)

    def test_screensaver_preserves_lock_gap_and_unrelated_config(self):
        self.run_helper("init")
        self.assertEqual(
            self.run_helper("set-screensaver", "600"),
            {"screensaver": 600, "sleep": 0, "lockDelay": 150},
        )
        shell = json.loads(self.shell.read_text())
        self.assertEqual(shell["idle"], {"screensaver": 600, "lock": 750})
        self.assertTrue(shell["unrelated"])

    def test_screensaver_off_keeps_lock_and_schedules_screensaver_after_it(self):
        self.run_helper("init")
        self.assertEqual(
            self.run_helper("set-screensaver", "0"),
            {"screensaver": 0, "sleep": 0, "lockDelay": 150},
        )
        self.assertEqual(json.loads(self.shell.read_text())["idle"], {"screensaver": 301, "lock": 300})
        self.assertEqual(
            self.run_helper("set-screensaver", "600"),
            {"screensaver": 600, "sleep": 0, "lockDelay": 150},
        )
        self.assertEqual(json.loads(self.shell.read_text())["idle"], {"screensaver": 600, "lock": 750})

    def test_sleep_only_changes_sandman_state(self):
        self.run_helper("init")
        before = self.shell.read_text()
        self.assertEqual(
            self.run_helper("set-sleep", "3600"),
            {"screensaver": 150, "sleep": 3600, "lockDelay": 150},
        )
        self.assertEqual(self.shell.read_text(), before)


if __name__ == "__main__":
    unittest.main()
