"""Console + CSV logging, with TensorBoard when it is installed.

CSV lands in <log_root>/<run_name>/episodes.csv so results stay comparable
across algorithms; TensorBoard events go to the same directory:
    tensorboard --logdir ai/logs
"""
from __future__ import annotations

import csv
from pathlib import Path
from typing import Any


class RunLogger:
    def __init__(self, log_root: Path, run_name: str) -> None:
        self.directory = log_root / run_name
        self.directory.mkdir(parents=True, exist_ok=True)
        self._csv_file = open(self.directory / "episodes.csv", "w", newline="", encoding="utf-8")
        self._csv = csv.writer(self._csv_file)
        self._csv.writerow(["episode", "reward", "steps", "kills", "wave", "time"])
        self._tensorboard = None
        try:
            from torch.utils.tensorboard import SummaryWriter
            self._tensorboard = SummaryWriter(str(self.directory))
        except ImportError:
            pass  # console + CSV only

    def log_episode(self, episode: int, reward: float, steps: int, info: dict[str, Any]) -> None:
        kills = info.get("kills", 0)
        wave = info.get("wave", 0)
        time_survived = info.get("time", 0.0)
        print(
            f"[ep {episode:4d}] reward {reward:+8.2f} | steps {steps:5d} "
            f"| kills {kills:3d} | wave {wave:3d} | survived {time_survived:6.1f}s"
        )
        self._csv.writerow([episode, f"{reward:.4f}", steps, kills, wave, f"{time_survived:.2f}"])
        self._csv_file.flush()
        if self._tensorboard is not None:
            self._tensorboard.add_scalar("episode/reward", reward, episode)
            self._tensorboard.add_scalar("episode/steps", steps, episode)
            self._tensorboard.add_scalar("episode/wave", wave, episode)

    def log_metrics(self, metrics: dict[str, float], step: int) -> None:
        if self._tensorboard is not None:
            for key, value in metrics.items():
                self._tensorboard.add_scalar(f"train/{key}", value, step)

    def close(self) -> None:
        self._csv_file.close()
        if self._tensorboard is not None:
            self._tensorboard.close()
