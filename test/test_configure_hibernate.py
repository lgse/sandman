import argparse
import importlib.machinery
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = ROOT / "sandman-configure-hibernate"


def load_helper():
    """Import the privileged helper, which has no .py extension."""
    loader = importlib.machinery.SourceFileLoader(
        "sandman_configure_hibernate", str(HELPER_PATH)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class SecondsValidationTest(unittest.TestCase):
    def setUp(self):
        self.helper = load_helper()

    def test_accepts_zero_and_positive_within_limit(self):
        self.assertEqual(self.helper.seconds("0"), 0)
        self.assertEqual(self.helper.seconds("7200"), 7200)
        self.assertEqual(
            self.helper.seconds(str(self.helper.MAX_TIMEOUT)),
            self.helper.MAX_TIMEOUT,
        )

    def test_rejects_non_integer(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            self.helper.seconds("later")

    def test_rejects_negative(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            self.helper.seconds("-1")

    def test_rejects_above_maximum(self):
        with self.assertRaises(argparse.ArgumentTypeError):
            self.helper.seconds(str(self.helper.MAX_TIMEOUT + 1))


class ConfigureHibernateMainTest(unittest.TestCase):
    def setUp(self):
        self.helper = load_helper()
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.config = Path(temporary.name) / "sleep.conf.d" / "90-sandman.conf"

    def run_main(self, *arguments, euid=0):
        argv = ["sandman-configure-hibernate", *arguments]
        with mock.patch.object(self.helper, "CONFIG", self.config), \
                mock.patch("os.geteuid", return_value=euid), \
                mock.patch.object(sys, "argv", argv):
            return self.helper.main()

    def test_requires_root(self):
        with self.assertRaises(SystemExit) as context:
            self.run_main("configure-hibernate", "7200", euid=1000)
        self.assertIn("administrator authorization is required", str(context.exception))
        self.assertFalse(self.config.exists())

    def test_writes_dropin_with_expected_content_and_mode(self):
        self.assertEqual(self.run_main("configure-hibernate", "7200"), 0)
        self.assertEqual(
            self.config.read_text(encoding="utf-8"),
            "[Sleep]\nHibernateDelaySec=7200s\nHibernateOnACPower=yes\n",
        )
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o644)

    def test_write_leaves_no_temporary_file_behind(self):
        self.run_main("configure-hibernate", "7200")
        siblings = [entry.name for entry in self.config.parent.iterdir()]
        self.assertEqual(siblings, [self.config.name])

    def test_zero_removes_existing_dropin(self):
        self.config.parent.mkdir(parents=True)
        self.config.write_text("stale\n", encoding="utf-8")
        self.assertEqual(self.run_main("configure-hibernate", "0"), 0)
        self.assertFalse(self.config.exists())

    def test_zero_without_existing_dropin_is_noop(self):
        self.assertEqual(self.run_main("configure-hibernate", "0"), 0)
        self.assertFalse(self.config.exists())

    def test_out_of_range_seconds_exits_without_writing(self):
        with self.assertRaises(SystemExit) as context:
            self.run_main("configure-hibernate", str(self.helper.MAX_TIMEOUT + 1))
        self.assertNotEqual(context.exception.code, 0)
        self.assertFalse(self.config.exists())


if __name__ == "__main__":
    unittest.main()
