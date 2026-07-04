"""Dreamer: model-based RL that learns a latent world model and trains an
actor-critic entirely inside imagined latent rollouts.

This is a COMPACT, DreamerV3-inspired implementation adapted to Valor 2's
vector observations (so the encoder/decoder are MLPs, not CNNs). It keeps the
essential pieces -- a recurrent state-space model (RSSM), reward/continue
predictors, KL-balanced representation learning, and actor-critic learning on
lambda-returns in imagination -- but omits heavier V3 machinery (discrete
latents, symlog/two-hot heads, percentile return normalization). Treat it as a
strong baseline to iterate on, not a paper-faithful reproduction.

References: Hafner et al., DreamerV1-V3.
"""
from __future__ import annotations

from collections import deque
from pathlib import Path
from typing import Any

import numpy as np

try:
    import torch
    from torch import nn
    from torch.distributions import Independent, Normal
    from torch.nn import functional as functional
except ImportError as error:  # pragma: no cover
    raise ImportError("Dreamer requires PyTorch: pip install torch") from error

from agents.base_agent import Agent
from environments.action_space import CONTINUOUS_ACTION_SIZE, continuous_to_action

DEFAULTS: dict[str, Any] = {
    "deter": 200,
    "stoch": 32,
    "hidden": 200,
    "embed": 200,
    "seq_len": 50,
    "batch_size": 16,
    "horizon": 15,
    "gamma": 0.99,
    "lam": 0.95,
    "kl_scale": 1.0,
    "kl_balance": 0.8,
    "free_nats": 1.0,
    "model_lr": 3e-4,
    "actor_lr": 8e-5,
    "critic_lr": 8e-5,
    "entropy_scale": 1e-3,
    "max_grad_norm": 100.0,
    "train_every": 16,
    "warmup_episodes": 5,
    "capacity": 100_000,
    "device": "cpu",
    "seed": 0,
}

_MIN_STD = 0.1


def _normal(mean: "torch.Tensor", std: "torch.Tensor") -> Independent:
    return Independent(Normal(mean, std), 1)


class WorldModel(nn.Module):
    def __init__(self, obs_size: int, action_size: int, cfg: dict[str, Any]) -> None:
        super().__init__()
        deter, stoch, hidden, embed = cfg["deter"], cfg["stoch"], cfg["hidden"], cfg["embed"]
        self.deter, self.stoch = deter, stoch
        self.encoder = nn.Sequential(
            nn.Linear(obs_size, hidden), nn.ELU(),
            nn.Linear(hidden, embed), nn.ELU())
        self.gru = nn.GRUCell(stoch + action_size, deter)
        self.prior_net = nn.Sequential(nn.Linear(deter, hidden), nn.ELU(), nn.Linear(hidden, 2 * stoch))
        self.post_net = nn.Sequential(nn.Linear(deter + embed, hidden), nn.ELU(), nn.Linear(hidden, 2 * stoch))
        self.decoder = nn.Sequential(
            nn.Linear(deter + stoch, hidden), nn.ELU(),
            nn.Linear(hidden, hidden), nn.ELU(),
            nn.Linear(hidden, obs_size))
        self.reward_head = nn.Sequential(nn.Linear(deter + stoch, hidden), nn.ELU(), nn.Linear(hidden, 1))
        self.continue_head = nn.Sequential(nn.Linear(deter + stoch, hidden), nn.ELU(), nn.Linear(hidden, 1))

    def _split(self, params: "torch.Tensor") -> Independent:
        mean, raw_std = params.chunk(2, dim=-1)
        return _normal(mean, functional.softplus(raw_std) + _MIN_STD)

    def prior(self, deter: "torch.Tensor") -> Independent:
        return self._split(self.prior_net(deter))

    def posterior(self, deter: "torch.Tensor", embed: "torch.Tensor") -> Independent:
        return self._split(self.post_net(torch.cat([deter, embed], dim=-1)))

    def step_deter(self, stoch: "torch.Tensor", action: "torch.Tensor",
                   deter: "torch.Tensor") -> "torch.Tensor":
        return self.gru(torch.cat([stoch, action], dim=-1), deter)

    def feature(self, deter: "torch.Tensor", stoch: "torch.Tensor") -> "torch.Tensor":
        return torch.cat([deter, stoch], dim=-1)


class Actor(nn.Module):
    def __init__(self, feature_size: int, action_size: int, hidden: int) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(feature_size, hidden), nn.ELU(),
            nn.Linear(hidden, hidden), nn.ELU())
        self.mean = nn.Linear(hidden, action_size)
        self.log_std = nn.Parameter(torch.full((action_size,), -0.5))

    def forward(self, feature: "torch.Tensor") -> Independent:
        hidden = self.net(feature)
        std = functional.softplus(self.log_std) + _MIN_STD
        return _normal(self.mean(hidden), std.expand_as(self.mean(hidden)))


class Critic(nn.Module):
    def __init__(self, feature_size: int, hidden: int) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(feature_size, hidden), nn.ELU(),
            nn.Linear(hidden, hidden), nn.ELU(),
            nn.Linear(hidden, 1))

    def forward(self, feature: "torch.Tensor") -> "torch.Tensor":
        return self.net(feature).squeeze(-1)


class SequenceReplay:
    """Stores whole episodes; samples fixed-length sub-sequences."""

    def __init__(self, capacity: int, seed: int) -> None:
        self.capacity = capacity
        self._episodes: deque = deque()
        self._steps = 0
        self._rng = np.random.default_rng(seed)

    def add_episode(self, obs, actions, rewards, dones) -> None:
        if len(obs) < 2:
            return
        episode = {
            "obs": np.asarray(obs, dtype=np.float32),
            "actions": np.asarray(actions, dtype=np.float32),
            "rewards": np.asarray(rewards, dtype=np.float32),
            "dones": np.asarray(dones, dtype=np.float32),
        }
        self._episodes.append(episode)
        self._steps += len(obs)
        while self._steps > self.capacity and len(self._episodes) > 1:
            self._steps -= len(self._episodes.popleft()["obs"])

    def can_sample(self, seq_len: int, batch_size: int) -> bool:
        usable = sum(1 for ep in self._episodes if len(ep["obs"]) >= seq_len)
        return usable >= 1 and len(self._episodes) >= 1 and self._steps >= seq_len * batch_size

    def sample(self, seq_len: int, batch_size: int):
        candidates = [ep for ep in self._episodes if len(ep["obs"]) >= seq_len]
        obs_b, act_b, rew_b, done_b = [], [], [], []
        for _ in range(batch_size):
            episode = candidates[self._rng.integers(len(candidates))]
            start = int(self._rng.integers(0, len(episode["obs"]) - seq_len + 1))
            end = start + seq_len
            obs_b.append(episode["obs"][start:end])
            act_b.append(episode["actions"][start:end])
            rew_b.append(episode["rewards"][start:end])
            done_b.append(episode["dones"][start:end])
        # -> [seq_len, batch, ...]
        return (
            np.swapaxes(np.stack(obs_b), 0, 1),
            np.swapaxes(np.stack(act_b), 0, 1),
            np.swapaxes(np.stack(rew_b), 0, 1),
            np.swapaxes(np.stack(done_b), 0, 1),
        )

    def episode_count(self) -> int:
        return len(self._episodes)


class DreamerAgent(Agent):
    name = "dreamer"
    is_recurrent = True

    def __init__(self, obs_size: int, config: dict[str, Any] | None = None) -> None:
        super().__init__(obs_size, {**DEFAULTS, **(config or {})})
        cfg = self.config
        torch.manual_seed(cfg["seed"])
        self.device = torch.device(cfg["device"])
        self.action_size = CONTINUOUS_ACTION_SIZE
        self.model = WorldModel(obs_size, self.action_size, cfg).to(self.device)
        feature_size = cfg["deter"] + cfg["stoch"]
        self.actor = Actor(feature_size, self.action_size, cfg["hidden"]).to(self.device)
        self.critic = Critic(feature_size, cfg["hidden"]).to(self.device)

        self.model_opt = torch.optim.Adam(self.model.parameters(), lr=cfg["model_lr"])
        self.actor_opt = torch.optim.Adam(self.actor.parameters(), lr=cfg["actor_lr"])
        self.critic_opt = torch.optim.Adam(self.critic.parameters(), lr=cfg["critic_lr"])

        self.buffer = SequenceReplay(cfg["capacity"], cfg["seed"])
        self.steps = 0
        self._reset_episode_storage()
        self._reset_latent()

    # --- acting -------------------------------------------------------------

    def on_episode_start(self) -> None:
        if self._ep_obs:  # flush the finished/truncated episode into replay
            self.buffer.add_episode(self._ep_obs, self._ep_actions, self._ep_rewards, self._ep_dones)
        self._reset_episode_storage()
        self._reset_latent()

    def select_action(self, observation: np.ndarray, explore: bool = True) -> dict:
        with torch.no_grad():
            obs = torch.as_tensor(observation, device=self.device).unsqueeze(0)
            embed = self.model.encoder(obs)
            self._deter = self.model.step_deter(self._stoch, self._prev_action, self._deter)
            post = self.model.posterior(self._deter, embed)
            self._stoch = post.rsample() if explore else post.mean
            feature = self.model.feature(self._deter, self._stoch)
            action_dist = self.actor(feature)
            raw_action = action_dist.rsample() if explore else action_dist.mean
            action = torch.tanh(raw_action)
            self._prev_action = action
        self._last_action = action.squeeze(0).cpu().numpy()
        return continuous_to_action(self._last_action)

    def observe(self, observation, action, reward, next_observation, terminated) -> None:
        self._ep_obs.append(np.asarray(observation, dtype=np.float32))
        self._ep_actions.append(self._last_action)
        self._ep_rewards.append(float(reward))
        self._ep_dones.append(float(terminated))
        self.steps += 1

    # --- learning -----------------------------------------------------------

    def update(self) -> dict[str, float]:
        cfg = self.config
        if self.buffer.episode_count() < cfg["warmup_episodes"]:
            return {}
        if self.steps % cfg["train_every"] != 0:
            return {}
        if not self.buffer.can_sample(cfg["seq_len"], cfg["batch_size"]):
            return {}

        obs, actions, rewards, dones = self.buffer.sample(cfg["seq_len"], cfg["batch_size"])
        obs_t = torch.as_tensor(obs, device=self.device)
        actions_t = torch.as_tensor(actions, device=self.device)
        rewards_t = torch.as_tensor(rewards, device=self.device)
        cont_t = 1.0 - torch.as_tensor(dones, device=self.device)

        model_loss, features, metrics = self._world_model_loss(obs_t, actions_t, rewards_t, cont_t)
        self.model_opt.zero_grad()
        model_loss.backward()
        nn.utils.clip_grad_norm_(self.model.parameters(), cfg["max_grad_norm"])
        self.model_opt.step()

        behavior_metrics = self._behavior_learning(features.detach())
        metrics.update(behavior_metrics)
        return metrics

    def _world_model_loss(self, obs, actions, rewards, cont):
        cfg = self.config
        seq_len, batch = obs.shape[0], obs.shape[1]
        deter = torch.zeros(batch, cfg["deter"], device=self.device)
        stoch = torch.zeros(batch, cfg["stoch"], device=self.device)
        prev_action = torch.zeros(batch, self.action_size, device=self.device)

        embeds = self.model.encoder(obs)
        features, kl_total = [], 0.0
        for t in range(seq_len):
            deter = self.model.step_deter(stoch, prev_action, deter)
            prior = self.model.prior(deter)
            post = self.model.posterior(deter, embeds[t])
            stoch = post.rsample()
            features.append(self.model.feature(deter, stoch))
            kl_total = kl_total + self._balanced_kl(post, prior)
            prev_action = actions[t]

        feature_stack = torch.stack(features)
        recon = self.model.decoder(feature_stack)
        recon_loss = 0.5 * ((recon - obs) ** 2).sum(dim=-1).mean()
        reward_pred = self.model.reward_head(feature_stack).squeeze(-1)
        reward_loss = 0.5 * ((reward_pred - rewards) ** 2).mean()
        cont_logit = self.model.continue_head(feature_stack).squeeze(-1)
        cont_loss = functional.binary_cross_entropy_with_logits(cont_logit, cont)
        kl_loss = kl_total / seq_len

        loss = recon_loss + reward_loss + cont_loss + cfg["kl_scale"] * kl_loss
        metrics = {
            "model_loss": float(loss.item()),
            "recon_loss": float(recon_loss.item()),
            "reward_loss": float(reward_loss.item()),
            "kl": float(kl_loss.item()),
        }
        return loss, feature_stack.reshape(seq_len * batch, -1), metrics

    def _balanced_kl(self, post: Independent, prior: Independent) -> "torch.Tensor":
        cfg = self.config
        free = cfg["free_nats"]
        kl_post = torch.distributions.kl_divergence(
            post, _detach_dist(prior)).clamp(min=free).mean()
        kl_prior = torch.distributions.kl_divergence(
            _detach_dist(post), prior).clamp(min=free).mean()
        return cfg["kl_balance"] * kl_prior + (1.0 - cfg["kl_balance"]) * kl_post

    def _behavior_learning(self, start_features) -> dict[str, float]:
        cfg = self.config
        deter, stoch = start_features.split([cfg["deter"], cfg["stoch"]], dim=-1)

        features, actions_entropy = [], []
        rewards, continues, values = [], [], []
        for _ in range(cfg["horizon"]):
            feature = self.model.feature(deter, stoch)
            features.append(feature)
            action_dist = self.actor(feature)
            raw_action = action_dist.rsample()
            actions_entropy.append(action_dist.entropy())
            action = torch.tanh(raw_action)
            rewards.append(self.model.reward_head(feature).squeeze(-1))
            continues.append(torch.sigmoid(self.model.continue_head(feature).squeeze(-1)))
            values.append(self.critic(feature))
            deter = self.model.step_deter(stoch, action, deter)
            stoch = self.model.prior(deter).rsample()
        # bootstrap value at the final imagined state
        values.append(self.critic(self.model.feature(deter, stoch)))

        rewards = torch.stack(rewards)
        discounts = cfg["gamma"] * torch.stack(continues)
        values_t = torch.stack(values)
        returns = self._lambda_return(rewards, values_t, discounts, cfg["lam"])

        entropy = torch.stack(actions_entropy).mean()
        actor_loss = -returns.mean() - cfg["entropy_scale"] * entropy
        self.actor_opt.zero_grad()
        actor_loss.backward()
        nn.utils.clip_grad_norm_(self.actor.parameters(), cfg["max_grad_norm"])
        self.actor_opt.step()

        value_pred = self.critic(torch.stack(features).detach())
        critic_loss = 0.5 * ((value_pred - returns.detach()) ** 2).mean()
        self.critic_opt.zero_grad()
        critic_loss.backward()
        nn.utils.clip_grad_norm_(self.critic.parameters(), cfg["max_grad_norm"])
        self.critic_opt.step()

        return {
            "actor_loss": float(actor_loss.item()),
            "critic_loss": float(critic_loss.item()),
            "imag_return": float(returns.mean().item()),
        }

    @staticmethod
    def _lambda_return(rewards, values, discounts, lam) -> "torch.Tensor":
        horizon = rewards.shape[0]
        returns = torch.zeros_like(rewards)
        last = values[-1]
        for t in reversed(range(horizon)):
            last = rewards[t] + discounts[t] * ((1.0 - lam) * values[t + 1] + lam * last)
            returns[t] = last
        return returns

    # --- state / io ---------------------------------------------------------

    def _reset_latent(self) -> None:
        self._deter = torch.zeros(1, self.config["deter"], device=self.device)
        self._stoch = torch.zeros(1, self.config["stoch"], device=self.device)
        self._prev_action = torch.zeros(1, self.action_size, device=self.device)
        self._last_action = np.zeros(self.action_size, dtype=np.float32)

    def _reset_episode_storage(self) -> None:
        self._ep_obs: list = []
        self._ep_actions: list = []
        self._ep_rewards: list = []
        self._ep_dones: list = []

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        torch.save({
            "model": self.model.state_dict(),
            "actor": self.actor.state_dict(),
            "critic": self.critic.state_dict(),
            "steps": self.steps,
        }, path)

    def load(self, path: Path) -> None:
        checkpoint = torch.load(path, map_location=self.device)
        self.model.load_state_dict(checkpoint["model"])
        self.actor.load_state_dict(checkpoint["actor"])
        self.critic.load_state_dict(checkpoint["critic"])
        self.steps = checkpoint.get("steps", 0)


def _detach_dist(dist: Independent) -> Independent:
    base = dist.base_dist
    return Independent(Normal(base.loc.detach(), base.scale.detach()), 1)
