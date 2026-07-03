"""Algorithm-agnostic training and evaluation loop with checkpointing.

Checkpoints go to <weights_root>/<algorithm>/<run_name>/:
    latest.pt   -- always the most recent
    best.pt     -- highest episode reward so far
    ep_00100.pt -- periodic snapshots
"""
from __future__ import annotations

import math
from pathlib import Path

from agents.base_agent import Agent
from environments.valor_env import ValorEnv
from utils.run_logger import RunLogger


class Trainer:
    def __init__(
        self,
        env: ValorEnv,
        agent: Agent,
        logger: RunLogger,
        run_name: str,
        weights_root: Path,
        checkpoint_every: int = 25,
    ) -> None:
        self.env = env
        self.agent = agent
        self.logger = logger
        self.checkpoint_every = checkpoint_every
        self.checkpoint_dir = weights_root / agent.name / run_name
        self._global_step = 0

    def train(self, episodes: int, seed: int = 0) -> None:
        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)
        best_reward = -math.inf
        for episode in range(1, episodes + 1):
            reward, steps, info = self._run_episode(seed + episode, explore=True, learn=True)
            self.logger.log_episode(episode, reward, steps, info)
            if reward > best_reward:
                best_reward = reward
                self.agent.save(self.checkpoint_dir / "best.pt")
            if episode % self.checkpoint_every == 0:
                self.agent.save(self.checkpoint_dir / f"ep_{episode:05d}.pt")
                self.agent.save(self.checkpoint_dir / "latest.pt")
        self.agent.save(self.checkpoint_dir / "latest.pt")
        print(f"Training done. Best episode reward: {best_reward:+.2f}")
        print(f"Checkpoints: {self.checkpoint_dir}")

    def evaluate(self, episodes: int, seed: int = 10_000) -> float:
        rewards = []
        for episode in range(1, episodes + 1):
            reward, steps, info = self._run_episode(seed + episode, explore=False, learn=False)
            self.logger.log_episode(episode, reward, steps, info)
            rewards.append(reward)
        mean = sum(rewards) / max(len(rewards), 1)
        print(f"Evaluation over {episodes} episodes: mean reward {mean:+.2f}")
        return mean

    def _run_episode(self, seed: int, explore: bool, learn: bool) -> tuple[float, int, dict]:
        observation, info = self.env.reset(seed)
        total_reward = 0.0
        steps = 0
        done = False
        while not done:
            action = self.agent.select_action(observation, explore=explore)
            next_observation, reward, terminated, truncated, info = self.env.step(action)
            if learn:
                self.agent.observe(observation, action, reward, next_observation, terminated)
                metrics = self.agent.update()
                if metrics:
                    self.logger.log_metrics(metrics, self._global_step)
            observation = next_observation
            total_reward += reward
            steps += 1
            self._global_step += 1
            done = terminated or truncated
        return total_reward, steps, info
