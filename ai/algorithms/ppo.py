"""Proximal Policy Optimization with a diagonal Gaussian policy over the
continuous action space [move_x, move_y, look_x].

Note: GAE is cut at terminated boundaries only; a truncation mid-rollout
bleeds a small amount of value across the reset. This matches most reference
implementations and is acceptable at this stage.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np

try:
    import torch
    from torch import nn
    from torch.distributions import Normal
except ImportError as error:  # pragma: no cover
    raise ImportError("PPO requires PyTorch: pip install torch") from error

from agents.base_agent import Agent
from environments.action_space import CONTINUOUS_ACTION_SIZE, continuous_to_action
from utils.torch_device import resolve_device

DEFAULTS: dict[str, Any] = {
    "hidden_sizes": [128, 128],
    "lr": 3e-4,
    "gamma": 0.99,
    "gae_lambda": 0.95,
    "clip_ratio": 0.2,
    "rollout_steps": 2048,
    "minibatch_size": 64,
    "update_epochs": 4,
    "entropy_coef": 0.01,
    "value_coef": 0.5,
    "max_grad_norm": 0.5,
    "device": "auto",  # GPU when available; override with "cpu"/"cuda:N"
    "seed": 0,
}


def _mlp(in_size: int, hidden_sizes: list[int], out_size: int) -> nn.Sequential:
    layers: list[nn.Module] = []
    previous = in_size
    for size in hidden_sizes:
        layers += [nn.Linear(previous, size), nn.Tanh()]
        previous = size
    layers.append(nn.Linear(previous, out_size))
    return nn.Sequential(*layers)


class ActorCritic(nn.Module):
    def __init__(self, obs_size: int, action_size: int, hidden_sizes: list[int]) -> None:
        super().__init__()
        self.actor = _mlp(obs_size, hidden_sizes, action_size)
        self.log_std = nn.Parameter(torch.full((action_size,), -0.5))
        self.critic = _mlp(obs_size, hidden_sizes, 1)

    def dist(self, obs: torch.Tensor) -> Normal:
        return Normal(self.actor(obs), self.log_std.exp())

    def value(self, obs: torch.Tensor) -> torch.Tensor:
        return self.critic(obs).squeeze(-1)


class PPOAgent(Agent):
    name = "ppo"

    def __init__(self, obs_size: int, config: dict[str, Any] | None = None) -> None:
        super().__init__(obs_size, {**DEFAULTS, **(config or {})})
        cfg = self.config
        torch.manual_seed(cfg["seed"])
        self.device = resolve_device(cfg["device"])
        self.net = ActorCritic(obs_size, CONTINUOUS_ACTION_SIZE, cfg["hidden_sizes"]).to(self.device)
        self.optimizer = torch.optim.Adam(self.net.parameters(), lr=cfg["lr"])
        self._clear_rollout()
        self._last: dict[str, Any] = {}

    def select_action(self, observation: np.ndarray, explore: bool = True) -> dict:
        obs = torch.as_tensor(observation, device=self.device).unsqueeze(0)
        with torch.no_grad():
            dist = self.net.dist(obs)
            raw = dist.sample() if explore else dist.mean
            self._last = {
                "raw_action": raw.squeeze(0).cpu().numpy(),
                "log_prob": float(dist.log_prob(raw).sum(dim=-1).item()),
                "value": float(self.net.value(obs).item()),
            }
        return continuous_to_action(self._last["raw_action"])

    def observe(self, observation, action, reward, next_observation, terminated) -> None:
        self._obs.append(np.asarray(observation, dtype=np.float32))
        self._actions.append(self._last["raw_action"])
        self._log_probs.append(self._last["log_prob"])
        self._values.append(self._last["value"])
        self._rewards.append(float(reward))
        self._dones.append(float(terminated))
        self._final_next_obs = np.asarray(next_observation, dtype=np.float32)
        self._final_terminated = terminated

    def update(self) -> dict[str, float]:
        cfg = self.config
        if len(self._rewards) < cfg["rollout_steps"]:
            return {}

        obs = torch.as_tensor(np.stack(self._obs), device=self.device)
        actions = torch.as_tensor(np.stack(self._actions), device=self.device)
        old_log_probs = torch.as_tensor(self._log_probs, device=self.device)
        advantages_np, returns_np = self._compute_gae()
        advantages = torch.as_tensor(advantages_np, device=self.device)
        returns = torch.as_tensor(returns_np, device=self.device)
        advantages = (advantages - advantages.mean()) / (advantages.std() + 1e-8)

        n = len(self._rewards)
        indices = np.arange(n)
        rng = np.random.default_rng(cfg["seed"])
        metrics = {"policy_loss": 0.0, "value_loss": 0.0, "entropy": 0.0}
        batches = 0
        for _ in range(cfg["update_epochs"]):
            rng.shuffle(indices)
            for start in range(0, n, cfg["minibatch_size"]):
                batch = indices[start:start + cfg["minibatch_size"]]
                dist = self.net.dist(obs[batch])
                log_probs = dist.log_prob(actions[batch]).sum(dim=-1)
                ratio = (log_probs - old_log_probs[batch]).exp()
                clipped = torch.clamp(ratio, 1 - cfg["clip_ratio"], 1 + cfg["clip_ratio"])
                policy_loss = -torch.min(
                    ratio * advantages[batch], clipped * advantages[batch]
                ).mean()
                value_loss = nn.functional.mse_loss(self.net.value(obs[batch]), returns[batch])
                entropy = dist.entropy().sum(dim=-1).mean()
                loss = (
                    policy_loss
                    + cfg["value_coef"] * value_loss
                    - cfg["entropy_coef"] * entropy
                )
                self.optimizer.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(self.net.parameters(), cfg["max_grad_norm"])
                self.optimizer.step()
                metrics["policy_loss"] += float(policy_loss.item())
                metrics["value_loss"] += float(value_loss.item())
                metrics["entropy"] += float(entropy.item())
                batches += 1

        self._clear_rollout()
        return {key: value / max(batches, 1) for key, value in metrics.items()}

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        torch.save({"model": self.net.state_dict()}, path)

    def load(self, path: Path) -> None:
        checkpoint = torch.load(path, map_location=self.device)
        self.net.load_state_dict(checkpoint["model"])

    def _compute_gae(self) -> tuple[np.ndarray, np.ndarray]:
        cfg = self.config
        rewards = np.asarray(self._rewards, dtype=np.float32)
        values = np.asarray(self._values, dtype=np.float32)
        dones = np.asarray(self._dones, dtype=np.float32)
        n = len(rewards)

        if self._final_terminated:
            bootstrap = 0.0
        else:
            with torch.no_grad():
                next_obs = torch.as_tensor(
                    self._final_next_obs, device=self.device
                ).unsqueeze(0)
                bootstrap = float(self.net.value(next_obs).item())

        advantages = np.zeros(n, dtype=np.float32)
        last_gae = 0.0
        for t in reversed(range(n)):
            next_value = values[t + 1] if t + 1 < n else bootstrap
            non_terminal = 1.0 - dones[t]
            delta = rewards[t] + cfg["gamma"] * next_value * non_terminal - values[t]
            last_gae = delta + cfg["gamma"] * cfg["gae_lambda"] * non_terminal * last_gae
            advantages[t] = last_gae
        return advantages, advantages + values

    def _clear_rollout(self) -> None:
        self._obs: list[np.ndarray] = []
        self._actions: list[np.ndarray] = []
        self._log_probs: list[float] = []
        self._values: list[float] = []
        self._rewards: list[float] = []
        self._dones: list[float] = []
        self._final_next_obs: np.ndarray | None = None
        self._final_terminated = False
