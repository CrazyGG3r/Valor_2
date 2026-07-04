"""Per-algorithm training status persisted at weights/<algo>/status.json.

The console reads this to show each algorithm's "trained level" without
loading any checkpoints or PyTorch.
"""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any

_DEFAULT: dict[str, Any] = {
    "algo": "",
    "episodes_trained": 0,
    "total_steps": 0,
    "best_reward": None,
    "last_reward": None,
    "updated_at": None,
}


def status_path(algo_dir: Path) -> Path:
    return Path(algo_dir) / "status.json"


def load_status(algo_dir: Path) -> dict[str, Any]:
    path = status_path(algo_dir)
    if path.exists():
        try:
            return {**_DEFAULT, **json.loads(path.read_text(encoding="utf-8"))}
        except (json.JSONDecodeError, OSError):
            pass
    return dict(_DEFAULT)


def save_status(algo_dir: Path, status: dict[str, Any]) -> None:
    Path(algo_dir).mkdir(parents=True, exist_ok=True)
    status["updated_at"] = datetime.now().isoformat(timespec="seconds")
    status_path(algo_dir).write_text(json.dumps(status, indent=2), encoding="utf-8")


def describe_level(status: dict[str, Any]) -> str:
    """One-line summary for the console table."""
    episodes = status.get("episodes_trained", 0)
    if not episodes:
        return "untrained"
    best = status.get("best_reward")
    best_text = f"{best:+.1f}" if best is not None else "n/a"
    return f"{episodes} eps | best {best_text}"
