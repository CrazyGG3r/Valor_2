"""Deep Q-Network over the discretized action set (environments.action_space).

Value-based methods need discrete actions, so the continuous move/look space
is quantized into DISCRETE_ACTION_COUNT combinations of direction, turn, and
combat button (attack/shoot/dash), plus dedicated upgrade-choice actions.
"""
from __future__ import annotations

import copy
from pathlib import Path
from typing import Any

import numpy as np

try:
    import torch
    from torch import nn
except ImportError as error:  # pragma: no cover
    raise ImportError("DQN requires PyTorch: pip install torch") from error

from agents.base_agent import Agent
from environments.action_space import DISCRETE_ACTION_COUNT, discrete_to_action
from utils.replay_buffer import ReplayBuffer
from utils.torch_device import resolve_device

DEFAULTS: dict[str, Any] = {
    "hidden_sizes": [128, 128],
    "lr": 3e-4,
    "gamma": 0.99,
    "buffer_size": 100_000,
    "batch_size": 64,
    "warmup_steps": 1_000,
    "target_update_every": 1_000,
    "epsilon_start": 1.0,
    "epsilon_end": 0.05,
    "epsilon_decay_steps": 50_000,
    "device": "auto",  # GPU when available; override with "cpu"/"cuda:N"
    "seed": 0,
}


def _mlp(in_size: int, hidden_sizes: list[int], out_size: int) -> nn.Sequential:
    layers: list[nn.Module] = []
    previous = in_size
    for size in hidden_sizes:
        layers += [nn.Linear(previous, size), nn.ReLU()]
        previous = size
    layers.append(nn.Linear(previous, out_size))
    return nn.Sequential(*layers)


class DQNAgent(Agent):
    name = "dqn"

    def __init__(self, obs_size: int, config: dict[str, Any] | None = None) -> None:
        super().__init__(obs_size, {**DEFAULTS, **(config or {})})
        cfg = self.config
        torch.manual_seed(cfg["seed"])
        self.device = resolve_device(cfg["device"])
        self.online = _mlp(obs_size, cfg["hidden_sizes"], DISCRETE_ACTION_COUNT).to(self.device)
        self.target = copy.deepcopy(self.online).eval()
        self.optimizer = torch.optim.Adam(self.online.parameters(), lr=cfg["lr"])
        self.buffer = ReplayBuffer(cfg["buffer_size"], obs_size, seed=cfg["seed"])
        self.steps = 0
        self._rng = np.random.default_rng(cfg["seed"])
        self._last_index = 0

    def select_action(self, observation: np.ndarray, explore: bool = True) -> dict:
        if explore and self._rng.random() < self._epsilon():
            index = int(self._rng.integers(DISCRETE_ACTION_COUNT))
        else:
            with torch.no_grad():
                obs = torch.as_tensor(observation, device=self.device).unsqueeze(0)
                index = int(self.online(obs).argmax(dim=1).item())
        self._last_index = index
        return discrete_to_action(index)

    def observe(self, observation, action, reward, next_observation, terminated) -> None:
        self.buffer.add(observation, self._last_index, reward, next_observation, terminated)
        self.steps += 1

    def update(self) -> dict[str, float]:
        cfg = self.config
        if len(self.buffer) < max(cfg["warmup_steps"], cfg["batch_size"]):
            return {}
        obs, actions, rewards, next_obs, dones = self.buffer.sample(cfg["batch_size"])
        obs_t = torch.as_tensor(obs, device=self.device)
        actions_t = torch.as_tensor(actions, device=self.device)
        rewards_t = torch.as_tensor(rewards, device=self.device)
        next_obs_t = torch.as_tensor(next_obs, device=self.device)
        dones_t = torch.as_tensor(dones, device=self.device)

        q_values = self.online(obs_t).gather(1, actions_t.unsqueeze(1)).squeeze(1)
        with torch.no_grad():
            next_q = self.target(next_obs_t).max(dim=1).values
            targets = rewards_t + cfg["gamma"] * next_q * (1.0 - dones_t)
        loss = nn.functional.smooth_l1_loss(q_values, targets)

        self.optimizer.zero_grad()
        loss.backward()
        self.optimizer.step()

        if self.steps % cfg["target_update_every"] == 0:
            self.target.load_state_dict(self.online.state_dict())
        return {"loss": float(loss.item()), "epsilon": self._epsilon()}

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        torch.save({"model": self.online.state_dict(), "steps": self.steps}, path)

    def load(self, path: Path) -> None:
        checkpoint = torch.load(path, map_location=self.device)
        self.online.load_state_dict(checkpoint["model"])
        self.target.load_state_dict(checkpoint["model"])
        self.steps = checkpoint.get("steps", 0)

    def _epsilon(self) -> float:
        cfg = self.config
        fraction = min(self.steps / max(cfg["epsilon_decay_steps"], 1), 1.0)
        return cfg["epsilon_start"] + fraction * (cfg["epsilon_end"] - cfg["epsilon_start"])
