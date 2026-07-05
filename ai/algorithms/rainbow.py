"""Rainbow DQN over the discretized action set (environments.action_space).

Combines the six Rainbow components on top of the DQN baseline:
  - Double DQN targets
  - Dueling network heads
  - Distributional value (C51)
  - NoisyNet exploration (replaces epsilon-greedy)
  - Prioritized experience replay (proportional)
  - Multi-step (n-step) returns

References: Hessel et al. 2018, "Rainbow: Combining Improvements in Deep RL".
"""
from __future__ import annotations

import math
from collections import deque
from pathlib import Path
from typing import Any

import numpy as np

try:
    import torch
    from torch import nn
    from torch.nn import functional as functional
except ImportError as error:  # pragma: no cover
    raise ImportError("Rainbow requires PyTorch: pip install torch") from error

from agents.base_agent import Agent
from environments.action_space import DISCRETE_ACTION_COUNT, discrete_to_action
from utils.segment_tree import MinSegmentTree, SumSegmentTree
from utils.torch_device import resolve_device

DEFAULTS: dict[str, Any] = {
    "hidden_size": 128,
    "lr": 6.25e-5,
    "gamma": 0.99,
    "buffer_size": 100_000,
    "batch_size": 64,
    "warmup_steps": 1_000,
    "target_update_every": 1_000,
    "n_step": 3,
    "atoms": 51,
    "v_min": -20.0,
    "v_max": 40.0,
    "noisy_sigma": 0.5,
    "priority_alpha": 0.5,
    "priority_beta_start": 0.4,
    "priority_beta_steps": 100_000,
    "max_grad_norm": 10.0,
    "device": "auto",  # GPU when available; override with "cpu"/"cuda:N"
    "seed": 0,
}


class NoisyLinear(nn.Module):
    """Factorized Gaussian NoisyNet layer. Uses mean weights in eval mode."""

    def __init__(self, in_features: int, out_features: int, sigma_init: float) -> None:
        super().__init__()
        self.in_features = in_features
        self.out_features = out_features
        self.weight_mu = nn.Parameter(torch.empty(out_features, in_features))
        self.weight_sigma = nn.Parameter(torch.empty(out_features, in_features))
        self.register_buffer("weight_epsilon", torch.empty(out_features, in_features))
        self.bias_mu = nn.Parameter(torch.empty(out_features))
        self.bias_sigma = nn.Parameter(torch.empty(out_features))
        self.register_buffer("bias_epsilon", torch.empty(out_features))
        self._sigma_init = sigma_init
        self.reset_parameters()
        self.reset_noise()

    def reset_parameters(self) -> None:
        bound = 1.0 / math.sqrt(self.in_features)
        self.weight_mu.data.uniform_(-bound, bound)
        self.weight_sigma.data.fill_(self._sigma_init / math.sqrt(self.in_features))
        self.bias_mu.data.uniform_(-bound, bound)
        self.bias_sigma.data.fill_(self._sigma_init / math.sqrt(self.out_features))

    @staticmethod
    def _scale_noise(size: int) -> "torch.Tensor":
        x = torch.randn(size)
        return x.sign().mul_(x.abs().sqrt_())

    def reset_noise(self) -> None:
        eps_in = self._scale_noise(self.in_features)
        eps_out = self._scale_noise(self.out_features)
        self.weight_epsilon.copy_(eps_out.outer(eps_in))
        self.bias_epsilon.copy_(eps_out)

    def forward(self, x: "torch.Tensor") -> "torch.Tensor":
        if self.training:
            weight = self.weight_mu + self.weight_sigma * self.weight_epsilon
            bias = self.bias_mu + self.bias_sigma * self.bias_epsilon
        else:
            weight, bias = self.weight_mu, self.bias_mu
        return functional.linear(x, weight, bias)


class RainbowNetwork(nn.Module):
    """Dueling + distributional network with noisy value/advantage streams."""

    def __init__(self, obs_size: int, actions: int, atoms: int,
                 hidden: int, sigma: float) -> None:
        super().__init__()
        self.actions = actions
        self.atoms = atoms
        self.feature = nn.Sequential(nn.Linear(obs_size, hidden), nn.ReLU())
        self.value_hidden = NoisyLinear(hidden, hidden, sigma)
        self.value_out = NoisyLinear(hidden, atoms, sigma)
        self.adv_hidden = NoisyLinear(hidden, hidden, sigma)
        self.adv_out = NoisyLinear(hidden, actions * atoms, sigma)

    def forward(self, x: "torch.Tensor") -> "torch.Tensor":
        """Returns per-action probability distributions [batch, actions, atoms]."""
        features = self.feature(x)
        value = self.value_out(functional.relu(self.value_hidden(features)))
        value = value.view(-1, 1, self.atoms)
        advantage = self.adv_out(functional.relu(self.adv_hidden(features)))
        advantage = advantage.view(-1, self.actions, self.atoms)
        q_atoms = value + advantage - advantage.mean(dim=1, keepdim=True)
        return functional.softmax(q_atoms, dim=2).clamp(min=1e-6)

    def reset_noise(self) -> None:
        for module in self.modules():
            if isinstance(module, NoisyLinear):
                module.reset_noise()


class PrioritizedReplay:
    """Proportional prioritized replay backed by segment trees."""

    def __init__(self, capacity: int, obs_size: int, alpha: float, seed: int) -> None:
        self.capacity = capacity
        self.alpha = alpha
        self._obs = np.zeros((capacity, obs_size), dtype=np.float32)
        self._actions = np.zeros(capacity, dtype=np.int64)
        self._rewards = np.zeros(capacity, dtype=np.float32)
        self._next_obs = np.zeros((capacity, obs_size), dtype=np.float32)
        self._dones = np.zeros(capacity, dtype=np.float32)
        self._gammas = np.zeros(capacity, dtype=np.float32)
        self._cursor = 0
        self._size = 0
        self._max_priority = 1.0
        tree_capacity = 1
        while tree_capacity < capacity:
            tree_capacity *= 2
        self._sum_tree = SumSegmentTree(tree_capacity)
        self._min_tree = MinSegmentTree(tree_capacity)
        self._rng = np.random.default_rng(seed)

    def add(self, obs, action, reward, next_obs, done, gamma_n) -> None:
        i = self._cursor
        self._obs[i] = obs
        self._actions[i] = action
        self._rewards[i] = reward
        self._next_obs[i] = next_obs
        self._dones[i] = float(done)
        self._gammas[i] = gamma_n
        self._sum_tree[i] = self._max_priority ** self.alpha
        self._min_tree[i] = self._max_priority ** self.alpha
        self._cursor = (self._cursor + 1) % self.capacity
        self._size = min(self._size + 1, self.capacity)

    def sample(self, batch_size: int, beta: float):
        indices = self._sample_proportional(batch_size)
        total = self._sum_tree.sum(0, self._size)
        min_prob = self._min_tree.min(0, self._size) / total
        max_weight = (min_prob * self._size) ** (-beta)
        probs = np.array([self._sum_tree[i] for i in indices]) / total
        weights = (probs * self._size) ** (-beta) / max_weight
        return (
            self._obs[indices],
            self._actions[indices],
            self._rewards[indices],
            self._next_obs[indices],
            self._dones[indices],
            self._gammas[indices],
            weights.astype(np.float32),
            indices,
        )

    def update_priorities(self, indices, priorities) -> None:
        for index, priority in zip(indices, priorities):
            priority = float(max(priority, 1e-6))
            self._sum_tree[index] = priority ** self.alpha
            self._min_tree[index] = priority ** self.alpha
            self._max_priority = max(self._max_priority, priority)

    def _sample_proportional(self, batch_size: int) -> list[int]:
        indices = []
        total = self._sum_tree.sum(0, self._size)
        segment = total / batch_size
        for i in range(batch_size):
            mass = self._rng.uniform(segment * i, segment * (i + 1))
            indices.append(self._sum_tree.find_prefixsum_index(mass))
        return indices

    def __len__(self) -> int:
        return self._size


class RainbowAgent(Agent):
    name = "rainbow"

    def __init__(self, obs_size: int, config: dict[str, Any] | None = None) -> None:
        super().__init__(obs_size, {**DEFAULTS, **(config or {})})
        cfg = self.config
        torch.manual_seed(cfg["seed"])
        self.device = resolve_device(cfg["device"])
        self.atoms = cfg["atoms"]
        self.n_step = cfg["n_step"]
        self.gamma = cfg["gamma"]
        self.support = torch.linspace(cfg["v_min"], cfg["v_max"], self.atoms, device=self.device)
        self.delta_z = (cfg["v_max"] - cfg["v_min"]) / (self.atoms - 1)

        self.online = RainbowNetwork(
            obs_size, DISCRETE_ACTION_COUNT, self.atoms, cfg["hidden_size"], cfg["noisy_sigma"]
        ).to(self.device)
        self.target = RainbowNetwork(
            obs_size, DISCRETE_ACTION_COUNT, self.atoms, cfg["hidden_size"], cfg["noisy_sigma"]
        ).to(self.device)
        self.target.load_state_dict(self.online.state_dict())
        self.target.eval()
        self.optimizer = torch.optim.Adam(self.online.parameters(), lr=cfg["lr"], eps=1.5e-4)
        self.buffer = PrioritizedReplay(cfg["buffer_size"], obs_size, cfg["priority_alpha"], cfg["seed"])
        self._n_step_queue: deque = deque(maxlen=self.n_step)
        self.steps = 0
        self._last_index = 0

    def select_action(self, observation: np.ndarray, explore: bool = True) -> dict:
        self.online.train(explore)  # eval mode uses mean weights (no noise)
        with torch.no_grad():
            if explore:
                self.online.reset_noise()
            obs = torch.as_tensor(observation, device=self.device).unsqueeze(0)
            expected_q = (self.online(obs) * self.support).sum(dim=2)
            index = int(expected_q.argmax(dim=1).item())
        self._last_index = index
        return discrete_to_action(index)

    def observe(self, observation, action, reward, next_observation, terminated) -> None:
        self._n_step_queue.append(
            (observation, self._last_index, reward, next_observation, terminated))
        if len(self._n_step_queue) >= self.n_step:
            self._push_n_step()
        if terminated:
            while self._n_step_queue:  # flush the tail with shorter horizons
                self._push_n_step()
        self.steps += 1

    def _push_n_step(self) -> None:
        obs, action, _, _, _ = self._n_step_queue[0]
        cumulative = 0.0
        gamma = 1.0
        next_obs = self._n_step_queue[-1][3]
        done = False
        for (_, _, reward, step_next, step_done) in self._n_step_queue:
            cumulative += gamma * reward
            gamma *= self.gamma
            next_obs = step_next
            done = step_done
            if step_done:
                break
        self.buffer.add(obs, action, cumulative, next_obs, done, gamma)
        self._n_step_queue.popleft()

    def update(self) -> dict[str, float]:
        cfg = self.config
        if len(self.buffer) < max(cfg["warmup_steps"], cfg["batch_size"]):
            return {}
        beta = min(1.0, cfg["priority_beta_start"]
                   + (1.0 - cfg["priority_beta_start"]) * self.steps / cfg["priority_beta_steps"])
        obs, actions, rewards, next_obs, dones, gammas, weights, indices = \
            self.buffer.sample(cfg["batch_size"], beta)

        obs_t = torch.as_tensor(obs, device=self.device)
        actions_t = torch.as_tensor(actions, device=self.device)
        rewards_t = torch.as_tensor(rewards, device=self.device)
        next_obs_t = torch.as_tensor(next_obs, device=self.device)
        dones_t = torch.as_tensor(dones, device=self.device)
        gammas_t = torch.as_tensor(gammas, device=self.device)
        weights_t = torch.as_tensor(weights, device=self.device)

        target_dist = self._projected_target(rewards_t, next_obs_t, dones_t, gammas_t)
        self.online.train(True)
        self.online.reset_noise()
        dist = self.online(obs_t)
        log_p = dist[range(cfg["batch_size"]), actions_t].clamp(min=1e-6).log()
        elementwise_loss = -(target_dist * log_p).sum(dim=1)
        loss = (elementwise_loss * weights_t).mean()

        self.optimizer.zero_grad()
        loss.backward()
        nn.utils.clip_grad_norm_(self.online.parameters(), cfg["max_grad_norm"])
        self.optimizer.step()

        self.buffer.update_priorities(indices, elementwise_loss.detach().cpu().numpy())
        if self.steps % cfg["target_update_every"] == 0:
            self.target.load_state_dict(self.online.state_dict())
        return {"loss": float(loss.item()), "beta": beta}

    def _projected_target(self, rewards_t, next_obs_t, dones_t, gammas_t) -> "torch.Tensor":
        batch = rewards_t.shape[0]
        with torch.no_grad():
            self.online.reset_noise()
            next_dist_online = self.online(next_obs_t)
            next_actions = (next_dist_online * self.support).sum(dim=2).argmax(dim=1)  # Double DQN
            self.target.reset_noise()
            next_dist = self.target(next_obs_t)[range(batch), next_actions]

            tz = rewards_t.unsqueeze(1) + gammas_t.unsqueeze(1) * (1.0 - dones_t.unsqueeze(1)) \
                * self.support.unsqueeze(0)
            tz = tz.clamp(self.config["v_min"], self.config["v_max"])
            b = (tz - self.config["v_min"]) / self.delta_z
            lower = b.floor().long()
            upper = b.ceil().long()
            lower[(upper > 0) & (lower == upper)] -= 1
            upper[(lower < (self.atoms - 1)) & (lower == upper)] += 1

            target_dist = torch.zeros(batch, self.atoms, device=self.device)
            offset = torch.arange(batch, device=self.device).unsqueeze(1) * self.atoms
            target_dist.view(-1).index_add_(
                0, (lower + offset).view(-1), (next_dist * (upper.float() - b)).view(-1))
            target_dist.view(-1).index_add_(
                0, (upper + offset).view(-1), (next_dist * (b - lower.float())).view(-1))
        return target_dist

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        torch.save({
            "online": self.online.state_dict(),
            "target": self.target.state_dict(),
            "optimizer": self.optimizer.state_dict(),
            "steps": self.steps,
        }, path)

    def load(self, path: Path) -> None:
        checkpoint = torch.load(path, map_location=self.device)
        self.online.load_state_dict(checkpoint["online"])
        self.target.load_state_dict(checkpoint["target"])
        if "optimizer" in checkpoint:
            self.optimizer.load_state_dict(checkpoint["optimizer"])
        self.steps = checkpoint.get("steps", 0)
