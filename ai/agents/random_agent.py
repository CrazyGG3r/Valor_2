"""Uniform-random baseline. Needs no learning framework; every experiment
should beat this before it is taken seriously."""
from __future__ import annotations

from typing import Any

import numpy as np

from agents.base_agent import Agent
from environments.action_space import CONTINUOUS_ACTION_SIZE, continuous_to_action


class RandomAgent(Agent):
    name = "random"

    def __init__(self, obs_size: int, config: dict[str, Any] | None = None) -> None:
        super().__init__(obs_size, config)
        self._rng = np.random.default_rng(self.config.get("seed"))

    def select_action(self, observation: np.ndarray, explore: bool = True) -> dict:
        return continuous_to_action(self._rng.uniform(-1.0, 1.0, CONTINUOUS_ACTION_SIZE))
