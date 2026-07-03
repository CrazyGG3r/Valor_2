"""Planned algorithms, declared so the registry and CLI stay stable.

Each becomes a real implementation of agents.base_agent.Agent when we get to
it -- shipping untested pseudo-implementations would be worse than being
explicit about what works today.
"""
from __future__ import annotations

from typing import Any

import numpy as np

from agents.base_agent import Agent


class _PlannedAgent(Agent):
    algorithm_name = "?"

    def __init__(self, obs_size: int, config: dict[str, Any] | None = None) -> None:
        raise NotImplementedError(
            f"{self.algorithm_name} is planned but not implemented yet. "
            "Available today: random, dqn, ppo."
        )

    def select_action(self, observation: np.ndarray, explore: bool = True) -> dict:
        raise NotImplementedError


class SACAgent(_PlannedAgent):
    name = "sac"
    algorithm_name = "SAC (Soft Actor-Critic)"


class A2CAgent(_PlannedAgent):
    name = "a2c"
    algorithm_name = "A2C (Advantage Actor-Critic)"


class DDPGAgent(_PlannedAgent):
    name = "ddpg"
    algorithm_name = "DDPG (Deep Deterministic Policy Gradient)"
