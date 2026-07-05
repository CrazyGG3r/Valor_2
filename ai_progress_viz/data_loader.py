"""Discover training runs and load their per-episode research records.

Stdlib only, so any notebook or script can depend on it without pulling in
matplotlib/pandas. See SCHEMA.md for the record layout.

    from ai_progress_viz import data_loader
    run = data_loader.load_run("rainbow-train-20260705-001259")
    print(run.name, len(run.episodes), run.series("reward"))
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# ai_progress_viz/ and ai/ are siblings under the repo root.
REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LOGS_DIR = REPO_ROOT / "ai" / "logs"
STATS_FILENAME = "episode_stats.jsonl"


@dataclass
class Run:
    """One training/eval run's episode records, in episode order."""

    name: str
    path: Path
    episodes: list[dict[str, Any]]

    def series(self, field: str, default: float = 0.0) -> list[float]:
        """Column of values for `field` across episodes (missing -> default)."""
        return [float(ep.get(field, default) or default) for ep in self.episodes]

    def column(self, field: str) -> list[Any]:
        """Raw column for `field` (keeps lists/dicts intact, e.g. upgrade_order)."""
        return [ep.get(field) for ep in self.episodes]


def list_runs(logs_dir: Path | str = DEFAULT_LOGS_DIR) -> list[Path]:
    """Run directories under `logs_dir` that contain an episode_stats.jsonl."""
    root = Path(logs_dir)
    if not root.exists():
        return []
    runs = [d for d in sorted(root.iterdir()) if (d / STATS_FILENAME).exists()]
    return runs


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with open(path, encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as error:
                # Tolerate a torn final line from a run killed mid-write.
                raise ValueError(
                    f"{path}:{line_number}: malformed JSON line") from error
    return records


def resolve_run_path(target: str | Path, logs_dir: Path | str = DEFAULT_LOGS_DIR) -> Path:
    """Accept a run name, a run directory, or a direct stats-file path."""
    candidate = Path(target)
    if candidate.is_file():
        return candidate
    if candidate.is_dir():
        return candidate / STATS_FILENAME
    named = Path(logs_dir) / str(target)
    if named.is_dir():
        return named / STATS_FILENAME
    raise FileNotFoundError(f"no run found for '{target}' under {logs_dir}")


def load_run(target: str | Path, logs_dir: Path | str = DEFAULT_LOGS_DIR) -> Run:
    """Load a run by name, directory, or stats-file path into a `Run`."""
    stats_path = resolve_run_path(target, logs_dir)
    return Run(
        name=stats_path.parent.name,
        path=stats_path,
        episodes=_read_jsonl(stats_path),
    )


def load_run_dataframe(target: str | Path, logs_dir: Path | str = DEFAULT_LOGS_DIR):
    """Same data as a pandas DataFrame. Requires pandas (raises if missing)."""
    try:
        import pandas as pd
    except ImportError as error:  # pragma: no cover
        raise ImportError(
            "load_run_dataframe requires pandas: pip install pandas") from error
    return pd.DataFrame(load_run(target, logs_dir).episodes)


if __name__ == "__main__":  # quick discovery aid
    found = list_runs()
    if not found:
        print(f"No runs with {STATS_FILENAME} under {DEFAULT_LOGS_DIR}")
    for run_dir in found:
        episodes = _read_jsonl(run_dir / STATS_FILENAME)
        print(f"{run_dir.name:40s} {len(episodes):5d} episodes")
