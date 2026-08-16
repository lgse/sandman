#!/usr/bin/env python3
"""Persist Sandman settings without discarding unrelated Omarchy config."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

DEFAULT_SCREENSAVER = 150
DEFAULT_LOCK = 300
DEFAULT_SLEEP = 0
OFF_TIMEOUT = 7 * 24 * 60 * 60
MAX_TIMEOUT = OFF_TIMEOUT


class ConfigError(Exception):
    """An existing config file could not be read, so we must not rewrite it."""


def shell_path() -> Path:
    override = os.environ.get("OMARCHY_SHELL_CONFIG_PATH")
    return Path(override).expanduser() if override else Path.home() / ".config/omarchy/shell.json"


def config_path() -> Path:
    override = os.environ.get("SANDMAN_CONFIG_PATH")
    return Path(override).expanduser() if override else Path.home() / ".config/omarchy/sandman.json"


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


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def current_config() -> dict[str, int]:
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
        "lock": stored_lock,
        "sleep": seconds(stored.get("sleep"), DEFAULT_SLEEP, allow_off=True),
    }


def initialize() -> dict[str, int]:
    config = current_config()
    # Always persist the normalized shape so existing installs gain new fields.
    atomic_write(config_path(), config)
    return config


def apply_idle_config(config: dict[str, int]) -> None:
    shell = read_json(shell_path(), {"version": 1}, strict=True)
    idle = shell.get("idle") if isinstance(shell.get("idle"), dict) else {}
    lock_timeout = config["lock"] if config["lock"] > 0 else OFF_TIMEOUT
    screensaver_timeout = (
        config["screensaver"]
        if config["screensaver"] > 0
        else lock_timeout + 1
    )
    shell["idle"] = {
        **idle,
        "screensaver": screensaver_timeout,
        "lock": lock_timeout,
    }
    atomic_write(shell_path(), shell)


def set_screensaver(value: int) -> dict[str, int]:
    config = current_config()
    # Fall back to the default, never to DEFAULT_SLEEP: with allow_off a 0
    # fallback would turn an unusable value into "Off" and silently stand the
    # screen saver down. Only an explicit 0 from the caller means Off.
    config["screensaver"] = seconds(value, DEFAULT_SCREENSAVER, allow_off=True)
    apply_idle_config(config)
    atomic_write(config_path(), config)
    return config


def set_lock(value: int) -> dict[str, int]:
    config = current_config()
    # Same reasoning as set_screensaver, and it matters more here: a 0 fallback
    # would disable auto-lock on malformed input.
    config["lock"] = seconds(value, DEFAULT_LOCK, allow_off=True)
    apply_idle_config(config)
    atomic_write(config_path(), config)
    return config


def set_sleep(value: int) -> dict[str, int]:
    value = seconds(value, DEFAULT_SLEEP, allow_off=True)
    config = current_config()
    config["sleep"] = value
    atomic_write(config_path(), config)
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
    lock = commands.add_parser("set-lock")
    lock.add_argument("seconds", type=timeout)
    sleep = commands.add_parser("set-sleep")
    sleep.add_argument("seconds", type=timeout)
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
        elif args.command == "set-lock":
            config = set_lock(args.seconds)
        else:
            config = set_sleep(args.seconds)
    except ConfigError as error:
        print(f"sandman: {error}", file=sys.stderr)
        return 1
    print(json.dumps(config, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
