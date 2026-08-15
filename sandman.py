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
DEFAULT_SLEEP = 0


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
    shell_lock = seconds(idle.get("lock"), 300)
    stored_screensaver = (
        seconds(stored.get("screensaver"), DEFAULT_SCREENSAVER, allow_off=True)
        if "screensaver" in stored
        else shell_screensaver
    )
    return {
        "screensaver": stored_screensaver,
        "sleep": seconds(stored.get("sleep"), DEFAULT_SLEEP, allow_off=True),
        "lockDelay": seconds(
            stored.get("lockDelay"),
            max(0, shell_lock - shell_screensaver),
            allow_off=True,
        ),
    }


def initialize() -> dict[str, int]:
    config = current_config()
    if not config_path().exists():
        atomic_write(config_path(), config)
    return config


def set_screensaver(value: int) -> dict[str, int]:
    value = seconds(value, DEFAULT_SLEEP, allow_off=True)
    shell = read_json(shell_path(), {"version": 1})
    idle = shell.get("idle") if isinstance(shell.get("idle"), dict) else {}
    config = current_config()
    current_lock = seconds(idle.get("lock"), 300)

    # Omarchy has no independent "screensaver off" value. Scheduling it one
    # second after lock makes lock win the idle race; lock then cancels the
    # pending screensaver. The user's lock timeout itself remains unchanged.
    if value == 0:
        shell["idle"] = {**idle, "screensaver": current_lock + 1}
    else:
        shell["idle"] = {
            **idle,
            "screensaver": value,
            "lock": value + config["lockDelay"],
        }
    atomic_write(shell_path(), shell)

    config["screensaver"] = value
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
    else:
        config = set_sleep(args.seconds)
    print(json.dumps(config, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
