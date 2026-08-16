#!/usr/bin/env python3
"""Persist Sandman settings without discarding unrelated Omarchy config."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

DEFAULT_SCREENSAVER = 150
DEFAULT_DISPLAY = 0
DEFAULT_LOCK = 300
DEFAULT_SLEEP = 0
DEFAULT_HIBERNATE = 0
DEFAULT_LID_ACTION = "system"
LID_ACTIONS = ("system", "nothing", "display", "sleep", "hibernate")
OFF_TIMEOUT = 7 * 24 * 60 * 60
MAX_TIMEOUT = OFF_TIMEOUT
HYPR_OVERRIDE_BEGIN = "-- BEGIN Sandman lid action override"
HYPR_OVERRIDE_END = "-- END Sandman lid action override"
HYPR_OVERRIDE_BLOCK = f"""{HYPR_OVERRIDE_BEGIN}
-- Sandman manages laptop lid-close actions. Omarchy's default lid-close
-- binding locks immediately on lid close, before Sandman can apply Do nothing
-- or Display off, so replace it with monitor/clamshell reconciliation only.
hl.unbind("switch:on:Lid Switch")
o.bind("switch:on:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell", {{ locked = true }})
{HYPR_OVERRIDE_END}
"""
MANAGED_LID_ACTIONS = {"nothing", "display", "sleep", "hibernate"}
SYSTEMD_SLEEP_CONFIG = Path("/etc/systemd/sleep.conf.d/90-sandman.conf")


class ConfigError(Exception):
    """An existing config file could not be read, so we must not rewrite it."""


def shell_path() -> Path:
    override = os.environ.get("OMARCHY_SHELL_CONFIG_PATH")
    return Path(override).expanduser() if override else Path.home() / ".config/omarchy/shell.json"


def config_path() -> Path:
    override = os.environ.get("SANDMAN_CONFIG_PATH")
    return Path(override).expanduser() if override else Path.home() / ".config/omarchy/sandman.json"


def hypr_bindings_path() -> Path:
    override = os.environ.get("SANDMAN_HYPR_BINDINGS_PATH")
    return Path(override).expanduser() if override else Path.home() / ".config/hypr/bindings.lua"


def systemd_sleep_config_path() -> Path:
    override = os.environ.get("SANDMAN_SYSTEMD_SLEEP_CONFIG_PATH")
    return Path(override).expanduser() if override else SYSTEMD_SLEEP_CONFIG


def read_json(
    path: Path, fallback: dict[str, Any], *, strict: bool = False
) -> dict[str, Any]:
    """Load a JSON object, distinguishing "absent" from "present but unusable".

    A missing file legitimately means "no settings yet", so the fallback applies.
    Anything else - unreadable, malformed, or not a JSON object - means the file
    holds content we failed to understand. When strict, refuse rather than return
    a fallback: callers merge into the result and write it back, so returning a
    fallback here would replace a config we could not read with a bare stub.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return fallback.copy()
    except (OSError, UnicodeError) as error:
        # UnicodeDecodeError subclasses ValueError, not OSError, so a file
        # holding invalid UTF-8 would otherwise escape as a traceback.
        if strict:
            raise ConfigError(f"Could not read {path}: {error}") from error
        return fallback.copy()

    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        if strict:
            raise ConfigError(
                f"{path} is not valid JSON ({error}). "
                "Fix or remove the file; refusing to overwrite it."
            ) from error
        return fallback.copy()

    if not isinstance(value, dict):
        if strict:
            raise ConfigError(
                f"{path} does not contain a JSON object; refusing to overwrite it."
            )
        return fallback.copy()
    return value


def seconds(value: Any, fallback: int, *, allow_off: bool = False) -> int:
    if isinstance(value, bool):
        return fallback
    try:
        result = int(value)
    except (TypeError, ValueError):
        return fallback
    if allow_off and result == 0:
        return 0
    if result <= 0:
        return fallback
    # Bound persisted values too, not just setter input. A sandman.json written
    # by an older version - or edited by hand - can hold a value large enough to
    # overflow sleepDelaySeconds * 1000 in the QML timer.
    return min(result, MAX_TIMEOUT)


def atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    text = json.dumps(value, indent=2) + "\n"
    atomic_write_text(path, text)


def lid_action(value: Any) -> str:
    return value if isinstance(value, str) and value in LID_ACTIONS else DEFAULT_LID_ACTION


def remove_hypr_override(text: str) -> str:
    pattern = re.compile(
        rf"\n?{re.escape(HYPR_OVERRIDE_BEGIN)}.*?{re.escape(HYPR_OVERRIDE_END)}\n?",
        re.DOTALL,
    )
    return pattern.sub("\n", text).rstrip() + ("\n" if text else "")


def sync_hypr_lid_override(action: str) -> None:
    """Install/remove the Hyprland lid binding override for managed actions."""
    if os.environ.get("SANDMAN_DISABLE_HYPR_SYNC"):
        return

    path = hypr_bindings_path()
    try:
        original = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        original = ""
    except (OSError, UnicodeError):
        return

    without_override = remove_hypr_override(original)
    if action in MANAGED_LID_ACTIONS:
        next_text = without_override.rstrip() + "\n\n" + HYPR_OVERRIDE_BLOCK
    else:
        next_text = without_override

    if next_text == original:
        return

    try:
        atomic_write_text(path, next_text)
    except OSError:
        return

    if os.environ.get("SANDMAN_SKIP_HYPR_RELOAD") or os.environ.get("SANDMAN_HYPR_BINDINGS_PATH"):
        return
    try:
        subprocess.run(["hyprctl", "reload"], check=False, capture_output=True, timeout=2)
    except (FileNotFoundError, subprocess.SubprocessError):
        pass


def current_config() -> dict[str, int | str]:
    # shell.json belongs to Omarchy and holds unrelated settings, so it is read
    # strictly. sandman.json is ours and fully derivable, so a damaged copy may
    # be rebuilt from defaults.
    shell = read_json(shell_path(), {}, strict=True)
    idle = shell.get("idle") if isinstance(shell.get("idle"), dict) else {}
    stored = read_json(config_path(), {})
    shell_screensaver = seconds(idle.get("screensaver"), DEFAULT_SCREENSAVER)
    shell_lock = seconds(idle.get("lock"), DEFAULT_LOCK)
    stored_screensaver = (
        seconds(stored.get("screensaver"), DEFAULT_SCREENSAVER, allow_off=True)
        if "screensaver" in stored
        else shell_screensaver
    )
    stored_lock = (
        seconds(stored.get("lock"), DEFAULT_LOCK, allow_off=True)
        if "lock" in stored
        else shell_lock
    )
    return {
        "screensaver": stored_screensaver,
        "display": seconds(stored.get("display"), DEFAULT_DISPLAY, allow_off=True),
        "lock": stored_lock,
        "sleep": seconds(stored.get("sleep"), DEFAULT_SLEEP, allow_off=True),
        "hibernate": seconds(stored.get("hibernate"), DEFAULT_HIBERNATE, allow_off=True),
        "lid": lid_action(stored.get("lid")),
    }


def initialize() -> dict[str, int | str]:
    config = current_config()
    # Always persist the normalized shape so existing installs gain new fields.
    atomic_write(config_path(), config)
    sync_hypr_lid_override(str(config["lid"]))
    return config


def effective_idle_timeouts(config: dict[str, int | str]) -> tuple[int, int]:
    lock = int(config["lock"])
    screensaver = int(config["screensaver"])
    lock_timeout = lock if lock > 0 else OFF_TIMEOUT
    screensaver_timeout = screensaver if screensaver > 0 else lock_timeout + 1
    return screensaver_timeout, lock_timeout


def apply_idle_config(config: dict[str, int | str]) -> None:
    shell = read_json(shell_path(), {"version": 1}, strict=True)
    idle = shell.get("idle") if isinstance(shell.get("idle"), dict) else {}
    screensaver_timeout, lock_timeout = effective_idle_timeouts(config)
    shell["idle"] = {
        **idle,
        "screensaver": screensaver_timeout,
        "lock": lock_timeout,
    }
    atomic_write(shell_path(), shell)


def rearm_native_idle(config: dict[str, int | str]) -> None:
    """Re-register Omarchy's IdleMonitor after changing its timeout.

    Quickshell currently leaves the old idle notification registered when only
    IdleMonitor.timeout changes. Toggling an enabled service fixes that without
    restarting the shell. Never override an intentional Stay Awake state.
    """
    if os.environ.get("OMARCHY_SHELL_CONFIG_PATH"):
        return

    screensaver_timeout, lock_timeout = effective_idle_timeouts(config)
    for _ in range(20):
        try:
            completed = subprocess.run(
                ["omarchy-shell", "idle", "status"],
                check=True,
                capture_output=True,
                text=True,
                timeout=1,
            )
            status = json.loads(completed.stdout)
        except (FileNotFoundError, subprocess.SubprocessError, json.JSONDecodeError):
            return

        if not status.get("enabled", False):
            return
        if (
            status.get("screensaver") == screensaver_timeout
            and status.get("lock") == lock_timeout
        ):
            try:
                subprocess.run(
                    ["omarchy-shell", "idle", "disable"],
                    check=True,
                    capture_output=True,
                    timeout=1,
                )
                subprocess.run(
                    ["omarchy-shell", "idle", "enable"],
                    check=True,
                    capture_output=True,
                    timeout=1,
                )
            except (FileNotFoundError, subprocess.SubprocessError):
                pass
            return
        time.sleep(0.05)


def set_screensaver(value: int) -> dict[str, int | str]:
    config = current_config()
    # Fall back to the default, never to DEFAULT_SLEEP: with allow_off a 0
    # fallback would turn an unusable value into "Off" and silently stand the
    # screen saver down. Only an explicit 0 from the caller means Off.
    config["screensaver"] = seconds(value, DEFAULT_SCREENSAVER, allow_off=True)
    apply_idle_config(config)
    atomic_write(config_path(), config)
    rearm_native_idle(config)
    return config


def set_lock(value: int) -> dict[str, int | str]:
    config = current_config()
    # Same reasoning as set_screensaver, and it matters more here: a 0 fallback
    # would disable auto-lock on malformed input.
    config["lock"] = seconds(value, DEFAULT_LOCK, allow_off=True)
    apply_idle_config(config)
    atomic_write(config_path(), config)
    rearm_native_idle(config)
    return config


def set_display(value: int) -> dict[str, int | str]:
    value = seconds(value, DEFAULT_DISPLAY, allow_off=True)
    config = current_config()
    config["display"] = value
    atomic_write(config_path(), config)
    return config


def set_sleep(value: int) -> dict[str, int | str]:
    value = seconds(value, DEFAULT_SLEEP, allow_off=True)
    config = current_config()
    config["sleep"] = value
    atomic_write(config_path(), config)
    return config


def set_hibernate(value: int) -> dict[str, int | str]:
    value = seconds(value, DEFAULT_HIBERNATE, allow_off=True)
    config = current_config()
    config["hibernate"] = value
    atomic_write(config_path(), config)
    return config


def configure_hibernate(value: int) -> None:
    """Set systemd's suspend-then-hibernate delay.

    systemd owns the RTC wake alarm needed while the computer is suspended, so
    this drop-in is necessarily system-wide. The normal UI invokes this command
    through pkexec. Tests may redirect the path without requiring privileges.
    """
    path = systemd_sleep_config_path()
    if not os.environ.get("SANDMAN_SYSTEMD_SLEEP_CONFIG_PATH") and os.geteuid() != 0:
        raise ConfigError("administrator authorization is required to change the hibernate delay")
    try:
        if value == 0:
            path.unlink(missing_ok=True)
            return
        atomic_write_text(
            path,
            "[Sleep]\n"
            f"HibernateDelaySec={value}s\n"
            "HibernateOnACPower=yes\n",
        )
    except OSError as error:
        raise ConfigError(f"Could not update {path}: {error}") from error


def set_lid(value: str) -> dict[str, int | str]:
    config = current_config()
    config["lid"] = value
    atomic_write(config_path(), config)
    sync_hypr_lid_override(value)
    return config


def timeout(raw: str) -> int:
    """Accept 0 (Off) or a positive timeout no larger than MAX_TIMEOUT.

    Rejecting out-of-range values here keeps a bad number from reaching the
    QML side, where the sleep timer multiplies seconds by 1000 into a 32-bit
    int and would overflow past roughly 24 days.
    """
    try:
        value = int(raw)
    except ValueError:
        raise argparse.ArgumentTypeError(f"{raw!r} is not a whole number of seconds")
    if value < 0:
        raise argparse.ArgumentTypeError("timeout cannot be negative")
    if value > MAX_TIMEOUT:
        raise argparse.ArgumentTypeError(f"timeout cannot exceed {MAX_TIMEOUT} seconds")
    return value


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("init")
    commands.add_parser("get")
    screensaver = commands.add_parser("set-screensaver")
    screensaver.add_argument("seconds", type=timeout)
    display = commands.add_parser("set-display")
    display.add_argument("seconds", type=timeout)
    lock = commands.add_parser("set-lock")
    lock.add_argument("seconds", type=timeout)
    sleep = commands.add_parser("set-sleep")
    sleep.add_argument("seconds", type=timeout)
    hibernate = commands.add_parser("set-hibernate")
    hibernate.add_argument("seconds", type=timeout)
    configure_hibernate_parser = commands.add_parser("configure-hibernate")
    configure_hibernate_parser.add_argument("seconds", type=timeout)
    lid = commands.add_parser("set-lid")
    lid.add_argument("action", choices=LID_ACTIONS)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "init":
            config = initialize()
        elif args.command == "get":
            config = current_config()
        elif args.command == "set-screensaver":
            config = set_screensaver(args.seconds)
        elif args.command == "set-display":
            config = set_display(args.seconds)
        elif args.command == "set-lock":
            config = set_lock(args.seconds)
        elif args.command == "set-sleep":
            config = set_sleep(args.seconds)
        elif args.command == "set-hibernate":
            config = set_hibernate(args.seconds)
        elif args.command == "configure-hibernate":
            configure_hibernate(args.seconds)
            config = {"hibernate": args.seconds}
        else:
            config = set_lid(args.action)
    except ConfigError as error:
        print(f"sandman: {error}", file=sys.stderr)
        return 1
    print(json.dumps(config, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
