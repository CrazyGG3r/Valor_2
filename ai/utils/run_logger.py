"""Console + CSV logging, with TensorBoard when it is installed.

Three sinks live under <log_root>/<run_name>/:
    episodes.csv         -- one compact row per episode (comparable across algos)
    episode_stats.jsonl  -- one JSON object per episode with the FULL stat blob
                            from GameManager.episode_stats(), for offline
                            analysis in ../ai_progress_viz. Never printed to the
                            training console.
    TensorBoard events   -- tensorboard --logdir ai/logs

The console stays a single concise line per episode on purpose; the extensive
research data goes to episode_stats.jsonl instead of scrolling past during
training.
"""
from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any


class RunLogger:
    def __init__(self, log_root: Path, run_name: str) -> None:
        self.directory = log_root / run_name
        self.directory.mkdir(parents=True, exist_ok=True)
        self._csv_file = open(self.directory / "episodes.csv", "w", newline="", encoding="utf-8")
        self._csv = csv.writer(self._csv_file)
        self._csv.writerow([
            "episode", "reward", "steps", "kills", "wave", "time",
            "shots_fired", "dashes", "melee_swings", "damage_dealt",
            "damage_taken", "upgrades", "upgrade_order",
        ])
        # Full per-episode records, one JSON object per line (streamable, easy to
        # append, and trivially loaded by ai_progress_viz.data_loader).
        self._stats_file = open(
            self.directory / "episode_stats.jsonl", "w", encoding="utf-8")
        self._tensorboard = None
        try:
            from torch.utils.tensorboard import SummaryWriter
            self._tensorboard = SummaryWriter(str(self.directory))
        except ImportError:
            pass  # console + CSV + JSONL only

    def log_episode(self, episode: int, reward: float, steps: int, info: dict[str, Any]) -> None:
        stats: dict[str, Any] = dict(info.get("stats", {}) or {})
        kills = info.get("kills", 0)
        wave = info.get("wave", 0)
        time_survived = info.get("time", 0.0)
        shots_fired = info.get("shots_fired", 0)
        dashes = info.get("dashes", 0)
        melee_swings = info.get("melee_swings", 0)
        upgrades = info.get("upgrades", []) or []
        upgrades_text = "; ".join(str(entry) for entry in upgrades)
        upgrade_order = stats.get("upgrade_order", []) or []
        order_text = " > ".join(str(entry) for entry in upgrade_order)
        damage_dealt = stats.get("damage_dealt", 0.0)
        damage_taken = stats.get("damage_taken", 0.0)

        # Console: one concise line. Extensive stats go to JSONL, not here.
        print(
            f"[ep {episode:4d}] reward {reward:+8.2f} | steps {steps:5d} "
            f"| kills {kills:3d} | wave {wave:3d} | survived {time_survived:6.1f}s "
            f"| shots {shots_fired:3d} | dashes {dashes:3d} | melee {melee_swings:3d}"
            f"{' | upgrades ' + upgrades_text if upgrades_text else ''}"
        )
        self._csv.writerow([
            episode, f"{reward:.4f}", steps, kills, wave, f"{time_survived:.2f}",
            shots_fired, dashes, melee_swings, f"{float(damage_dealt):.2f}",
            f"{float(damage_taken):.2f}", upgrades_text, order_text,
        ])
        self._csv_file.flush()

        record = {"episode": episode, "reward": reward, "steps": steps, **stats}
        self._stats_file.write(json.dumps(record) + "\n")
        self._stats_file.flush()

        if self._tensorboard is not None:
            self._tensorboard.add_scalar("episode/reward", reward, episode)
            self._tensorboard.add_scalar("episode/steps", steps, episode)
            self._tensorboard.add_scalar("episode/wave", wave, episode)
            self._tensorboard.add_scalar("episode/kills", kills, episode)
            self._tensorboard.add_scalar("episode/shots_fired", shots_fired, episode)
            self._tensorboard.add_scalar("episode/dashes", dashes, episode)
            self._tensorboard.add_scalar("episode/melee_swings", melee_swings, episode)
            self._tensorboard.add_scalar("episode/damage_dealt", float(damage_dealt), episode)
            self._tensorboard.add_scalar("episode/damage_taken", float(damage_taken), episode)

    def log_metrics(self, metrics: dict[str, float], step: int) -> None:
        if self._tensorboard is not None:
            for key, value in metrics.items():
                self._tensorboard.add_scalar(f"train/{key}", value, step)

    def close(self) -> None:
        self._csv_file.close()
        self._stats_file.close()
        if self._tensorboard is not None:
            self._tensorboard.close()
