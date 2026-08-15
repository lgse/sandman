#!/usr/bin/env python3
"""Persist Sandman settings without discarding unrelated Omarchy config."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

DEFAULT_SCREENSAVER = 150
DEFAULT_LOCK = 300
DEFAULT_SLEEP = 0
OFF_TIMEOUT = 7 * 24 * 60 * 60


def shell_path() -> Path:
    override = os.environ.get("OMARCHY_SHELL_CONFIG_PATH")
    return Path(override).expanduser() if override else Path.home() / ".config/omarchy/shell.json"


def config_path() -> Path:
    override = os.environ.get("SANDMAN_CONFIG_PATH")
    return Path(override).expanduser() if override else Path.home() / ".config/omarchy/sandman.json"


def read_json(path: Path, fallback: dict[str, Any]) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else fallback.copy()
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return fallback.copy()


def seconds(value: Any, fallback: int, *, allow_off: bool = False) -> int:
    if isinstance(value, bool):
        return fallback
    try:
        result = int(value)
    except (TypeError, ValueError):
        return fallback
    if allow_off and result == 0:
        return 0
    return result if result > 0 else fallback


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
    shell = read_json(shell_path(), {})
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
    shell = read_json(shell_path(), {"version": 1})
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
    config["screensaver"] = seconds(value, DEFAULT_SLEEP, allow_off=True)
    apply_idle_config(config)
    atomic_write(config_path(), config)
    return config


def set_lock(value: int) -> dict[str, int]:
    config = current_config()
    config["lock"] = seconds(value, DEFAULT_SLEEP, allow_off=True)
    apply_idle_config(config)
    atomic_write(config_path(), config)
    return config


def set_sleep(value: int) -> dict[str, int]:
    value = seconds(value, DEFAULT_SLEEP, allow_off=True)
    config = current_config()
    config["sleep"] = value
    atomic_write(config_path(), config)
    return config


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    commands.add_parser("init")
    commands.add_parser("get")
    screensaver = commands.add_parser("set-screensaver")
    screensaver.add_argument("seconds", type=int)
    lock = commands.add_parser("set-lock")
    lock.add_argument("seconds", type=int)
    sleep = commands.add_parser("set-sleep")
    sleep.add_argument("seconds", type=int)
    return result


def main() -> int:
    args = parser().parse_args()
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
    print(json.dumps(config, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
