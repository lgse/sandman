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
        self.hypr_bindings = base / "bindings.lua"
        self.systemd_sleep_config = base / "90-sandman.conf"
        self.power_state = base / "power-state"
        self.power_resume = base / "power-resume"
        self.proc_swaps = base / "proc-swaps"
        self.proc_meminfo = base / "proc-meminfo"
        self.lockdown = base / "lockdown"
        self.efi = base / "efi"
        self.power_state.write_text("freeze mem disk\n", encoding="utf-8")
        self.power_resume.write_text("0:0\n", encoding="utf-8")
        self.proc_swaps.write_text("Filename Type Size Used Priority\n", encoding="utf-8")
        self.proc_meminfo.write_text("MemTotal: 8388608 kB\n", encoding="utf-8")
        self.lockdown.write_text("[none] integrity confidentiality\n", encoding="utf-8")
        self.efi.mkdir()
        self.hypr_bindings.write_text("-- user bindings\n", encoding="utf-8")
        self.shell.write_text(
            json.dumps({"version": 1, "idle": {"screensaver": 150, "lock": 300}, "unrelated": True}),
            encoding="utf-8",
        )
        self.environment = {
            **os.environ,
            "OMARCHY_SHELL_CONFIG_PATH": str(self.shell),
            "SANDMAN_CONFIG_PATH": str(self.config),
            "SANDMAN_HYPR_BINDINGS_PATH": str(self.hypr_bindings),
            "SANDMAN_SYSTEMD_SLEEP_CONFIG_PATH": str(self.systemd_sleep_config),
            "SANDMAN_POWER_STATE_PATH": str(self.power_state),
            "SANDMAN_POWER_RESUME_PATH": str(self.power_resume),
            "SANDMAN_PROC_SWAPS_PATH": str(self.proc_swaps),
            "SANDMAN_PROC_MEMINFO_PATH": str(self.proc_meminfo),
            "SANDMAN_LOCKDOWN_PATH": str(self.lockdown),
            "SANDMAN_EFI_PATH": str(self.efi),
            "SANDMAN_SKIP_HYPR_RELOAD": "1",
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

    def run_helper_expecting_failure(self, *arguments):
        completed = subprocess.run(
            ["python3", str(HELPER), *arguments],
            env=self.environment,
            check=False,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(completed.returncode, 0, completed.stdout)
        return completed

    def test_init_inherits_omarchy_idle_settings_and_disables_sleep(self):
        expected = {"screensaver": 150, "display": 0, "lock": 300, "sleep": 0, "hibernate": 0, "lid": "system"}
        self.assertEqual(self.run_helper("init"), expected)
        self.assertEqual(json.loads(self.config.read_text()), expected)

    def test_init_migrates_existing_config_to_include_new_fields(self):
        self.config.write_text(
            json.dumps({"screensaver": 150, "sleep": 3600, "lockDelay": 150}),
            encoding="utf-8",
        )

        expected = {"screensaver": 150, "display": 0, "lock": 300, "sleep": 3600, "hibernate": 0, "lid": "system"}
        self.assertEqual(self.run_helper("init"), expected)
        self.assertEqual(json.loads(self.config.read_text()), expected)

    def test_screensaver_preserves_lock_and_unrelated_config(self):
        self.run_helper("init")
        self.assertEqual(
            self.run_helper("set-screensaver", "600"),
            {"screensaver": 600, "display": 0, "lock": 300, "sleep": 0, "hibernate": 0, "lid": "system"},
        )
        shell = json.loads(self.shell.read_text())
        self.assertEqual(shell["idle"], {"screensaver": 600, "lock": 300})
        self.assertTrue(shell["unrelated"])

    def test_lock_only_changes_auto_lock_timeout(self):
        self.run_helper("init")
        self.assertEqual(
            self.run_helper("set-lock", "900"),
            {"screensaver": 150, "display": 0, "lock": 900, "sleep": 0, "hibernate": 0, "lid": "system"},
        )
        shell = json.loads(self.shell.read_text())
        self.assertEqual(shell["idle"], {"screensaver": 150, "lock": 900})

    def test_off_uses_safe_long_timeouts(self):
        self.run_helper("init")
        self.run_helper("set-lock", "0")
        self.assertEqual(
            self.run_helper("set-screensaver", "0"),
            {"screensaver": 0, "display": 0, "lock": 0, "sleep": 0, "hibernate": 0, "lid": "system"},
        )
        shell = json.loads(self.shell.read_text())
        self.assertEqual(
            shell["idle"],
            {"screensaver": 604801, "lock": 604800},
        )

    def test_sleep_only_changes_sandman_state(self):
        self.run_helper("init")
        before = self.shell.read_text()
        self.assertEqual(
            self.run_helper("set-sleep", "3600"),
            {"screensaver": 150, "display": 0, "lock": 300, "sleep": 3600, "hibernate": 0, "lid": "system"},
        )
        self.assertEqual(self.shell.read_text(), before)

    def test_hibernate_diagnostics_explain_missing_disk_backed_swap(self):
        result = self.run_helper("diagnose-hibernate")

        self.assertTrue(result["kernelHibernate"])
        self.assertEqual(result["suitableSwapKiB"], 0)
        self.assertTrue(result["efiAvailable"])
        self.assertIn("No disk-backed swap is active", result["summary"])

    def test_hibernate_diagnostics_report_kernel_resume_and_lockdown_issues(self):
        self.power_state.write_text("freeze mem\n", encoding="utf-8")
        self.efi.rmdir()
        self.lockdown.write_text("none integrity [confidentiality]\n", encoding="utf-8")
        self.proc_swaps.write_text(
            "Filename Type Size Used Priority\n/dev/sda2 partition 16777216 0 -2\n",
            encoding="utf-8",
        )

        result = self.run_helper("diagnose-hibernate")

        self.assertFalse(result["kernelHibernate"])
        self.assertIn("kernel does not advertise", result["summary"])
        self.assertIn("No kernel resume device", result["summary"])
        self.assertIn("lockdown confidentiality", result["summary"])

    def test_hibernate_delay_changes_sandman_state(self):
        self.run_helper("init")
        before = self.shell.read_text()
        self.assertEqual(
            self.run_helper("set-hibernate", "7200"),
            {"screensaver": 150, "display": 0, "lock": 300, "sleep": 0, "hibernate": 7200, "lid": "system"},
        )
        self.assertEqual(self.shell.read_text(), before)

    def test_configure_hibernate_writes_and_removes_systemd_dropin(self):
        completed = self.run_helper_expecting_failure("configure-hibernate", "7200")
        self.assertIn("administrator authorization is required", completed.stderr)
        self.assertFalse(self.systemd_sleep_config.exists())

    def test_display_only_changes_sandman_state(self):
        self.run_helper("init")
        before = self.shell.read_text()
        self.assertEqual(
            self.run_helper("set-display", "300"),
            {"screensaver": 150, "display": 300, "lock": 300, "sleep": 0, "hibernate": 0, "lid": "system"},
        )
        self.assertEqual(self.shell.read_text(), before)

    def test_lid_action_installs_hyprland_override(self):
        self.run_helper("init")
        before = self.shell.read_text()
        self.assertEqual(
            self.run_helper("set-lid", "display"),
            {"screensaver": 150, "display": 0, "lock": 300, "sleep": 0, "hibernate": 0, "lid": "display"},
        )
        self.assertEqual(self.shell.read_text(), before)
        bindings = self.hypr_bindings.read_text(encoding="utf-8")
        self.assertIn("BEGIN Sandman lid action override", bindings)
        self.assertIn('hl.unbind("switch:on:Lid Switch")', bindings)
        self.assertIn("omarchy-hyprland-monitor-clamshell", bindings)

    def test_system_lid_action_removes_hyprland_override(self):
        self.config.write_text(json.dumps({"lid": "display"}), encoding="utf-8")
        self.run_helper("init")
        self.assertIn(
            "BEGIN Sandman lid action override",
            self.hypr_bindings.read_text(encoding="utf-8"),
        )

        self.run_helper("set-lid", "system")

        bindings = self.hypr_bindings.read_text(encoding="utf-8")
        self.assertNotIn("BEGIN Sandman lid action override", bindings)
        self.assertEqual(bindings, "-- user bindings\n")

    def test_invalid_lid_action_is_rejected(self):
        self.run_helper("init")
        self.run_helper_expecting_failure("set-lid", "poweroff")
        self.assertEqual(json.loads(self.config.read_text())["lid"], "system")

    def test_invalid_utf8_shell_config_reports_cleanly_and_is_left_intact(self):
        self.run_helper("init")
        damaged = b'{"version": 1, "idle": {"lock": 300}, "x": "\xff\xfe"}'
        self.shell.write_bytes(damaged)

        completed = self.run_helper_expecting_failure("set-lock", "900")

        # A controlled message, not a UnicodeDecodeError traceback.
        self.assertIn("sandman:", completed.stderr)
        self.assertNotIn("Traceback", completed.stderr)
        self.assertEqual(self.shell.read_bytes(), damaged)

    def test_oversized_persisted_value_is_bounded(self):
        self.config.write_text(
            json.dumps({"screensaver": 150, "lock": 300, "sleep": 2000000000}),
            encoding="utf-8",
        )

        result = self.run_helper("init")

        # Must stay under the 32-bit limit of sleepDelaySeconds * 1000.
        self.assertEqual(result["sleep"], 7 * 24 * 60 * 60)
        self.assertLess(result["sleep"] * 1000, 2**31 - 1)
        self.assertEqual(json.loads(self.config.read_text())["sleep"], 7 * 24 * 60 * 60)

    def test_malformed_shell_config_is_left_intact(self):
        self.run_helper("init")
        damaged = '{"version": 1, "idle": {"lock": 300}, "bar": {"position": "top"},}'
        self.shell.write_text(damaged, encoding="utf-8")

        self.run_helper_expecting_failure("set-lock", "900")

        self.assertEqual(self.shell.read_text(encoding="utf-8"), damaged)

    def test_unreadable_shell_config_is_left_intact(self):
        self.run_helper("init")
        original = self.shell.read_text(encoding="utf-8")
        self.shell.chmod(0o000)
        try:
            self.run_helper_expecting_failure("set-lock", "900")
        finally:
            self.shell.chmod(0o644)

        self.assertEqual(self.shell.read_text(encoding="utf-8"), original)

    def test_negative_timeout_is_rejected_rather_than_disabling_lock(self):
        self.run_helper("init")

        self.run_helper_expecting_failure("set-lock", "-5")

        shell = json.loads(self.shell.read_text())
        self.assertEqual(shell["idle"]["lock"], 300)
        self.assertEqual(json.loads(self.config.read_text())["lock"], 300)

    def test_absurd_timeout_is_rejected(self):
        self.run_helper("init")

        self.run_helper_expecting_failure("set-sleep", "2000000000")

        self.assertEqual(json.loads(self.config.read_text())["sleep"], 0)

    def test_missing_shell_config_still_initializes(self):
        self.shell.unlink()
        self.assertEqual(
            self.run_helper("init"),
            {"screensaver": 150, "display": 0, "lock": 300, "sleep": 0, "hibernate": 0, "lid": "system"},
        )

    def test_damaged_sandman_config_is_rebuilt_from_shell(self):
        self.config.write_text("{not json", encoding="utf-8")
        self.assertEqual(
            self.run_helper("init"),
            {"screensaver": 150, "display": 0, "lock": 300, "sleep": 0, "hibernate": 0, "lid": "system"},
        )


if __name__ == "__main__":
    unittest.main()
