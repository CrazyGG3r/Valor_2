"""Abstract agent contract. Every algorithm implements exactly this interface,
so the trainer never knows which algorithm it is running -- swapping algorithms
is a CLI flag, never a code change."""
from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

import numpy as np


class Agent(ABC):
    name: str = "agent"
    ## Recurrent agents (e.g. Dreamer) carry hidden state across a run and
    ## must reset it via on_episode_start(). The trainer honors this flag only
    ## for documentation; it always calls on_episode_start regardless.
    is_recurrent: bool = False

    def __init__(self, obs_size: int, config: dict[str, Any] | None = None) -> None:
        self.obs_size = obs_size
        self.config = config or {}

    @abstractmethod
    def select_action(self, observation: np.ndarray, explore: bool = True) -> dict:
        """Return a wire action dict (see environments.action_space)."""

    def on_episode_start(self) -> None:
        """Called by the trainer right after env.reset(), before the first
        action. Recurrent agents reset their hidden state here."""

    def observe(
        self,
        observation: np.ndarray,
        action: dict,
        reward: float,
        next_observation: np.ndarray,
        terminated: bool,
    ) -> None:
        """Receive the transition produced by the last select_action call."""

    def update(self) -> dict[str, float]:
        """Run one learning step if ready. Returns loss metrics (may be empty)."""
        return {}

    def save(self, path: Path) -> None:
        """Persist weights/state to path. No-op for learning-free agents."""

    def load(self, path: Path) -> None:
        """Restore weights/state from path."""
