"""Algorithm-agnostic training and evaluation loop.

Checkpoints and progress live under a single per-algorithm directory
(weights/<algo>/) so the console can present one canonical "best" per
algorithm:
    best.pt      -- highest episode reward ever recorded for this algorithm
    latest.pt    -- most recent weights (used to resume training)
    ep_00100.pt  -- periodic snapshots
    status.json  -- cumulative episodes/steps and best reward

train() and evaluate() accept a should_stop callback polled every step, so the
console can stop-and-save on a keypress without SIGINT.
"""
from __future__ import annotations

import math
from pathlib import Path
from typing import Callable

from agents.base_agent import Agent
from environments.valor_env import ValorEnv
from utils.run_logger import RunLogger
from utils.status import load_status, save_status

StopFn = Callable[[], bool]


class Trainer:
    def __init__(
        self,
        env: ValorEnv,
        agent: Agent,
        logger: RunLogger,
        algo_dir: Path,
        checkpoint_every: int = 25,
    ) -> None:
        self.env = env
        self.agent = agent
        self.logger = logger
        self.algo_dir = Path(algo_dir)
        self.checkpoint_every = checkpoint_every
        self._global_step = 0

    def train(
        self,
        episodes: int,
        seed: int = 0,
        resume: bool = False,
        should_stop: StopFn | None = None,
    ) -> dict:
        self.algo_dir.mkdir(parents=True, exist_ok=True)
        status = load_status(self.algo_dir)
        status["algo"] = self.agent.name
        if resume and (self.algo_dir / "latest.pt").exists():
            self.agent.load(self.algo_dir / "latest.pt")
            print(f"Resumed from {self.algo_dir / 'latest.pt'} "
                  f"({status['episodes_trained']} episodes so far)")
        best_reward = status.get("best_reward")
        best_reward = -math.inf if best_reward is None else float(best_reward)

        stopped = False
        completed = 0
        for episode in range(1, episodes + 1):
            reward, steps, info, stopped = self._run_episode(
                seed + status["episodes_trained"] + episode,
                explore=True, learn=True, should_stop=should_stop)
            completed += 1
            status["episodes_trained"] += 1
            status["total_steps"] += steps
            status["last_reward"] = reward
            self.logger.log_episode(status["episodes_trained"], reward, steps, info)

            self.agent.save(self.algo_dir / "latest.pt")
            if reward > best_reward:
                best_reward = reward
                status["best_reward"] = reward
                self.agent.save(self.algo_dir / "best.pt")
            if status["episodes_trained"] % self.checkpoint_every == 0:
                self.agent.save(self.algo_dir / f"ep_{status['episodes_trained']:05d}.pt")
            save_status(self.algo_dir, status)
            if stopped:
                break

        print(f"{'Stopped' if stopped else 'Training done'} after {completed} episode(s). "
              f"Best reward: {best_reward:+.2f}")
        return {"stopped": stopped, "episodes": completed, "best_reward": best_reward}

    def evaluate(
        self,
        episodes: int,
        seed: int = 10_000,
        should_stop: StopFn | None = None,
    ) -> dict:
        rewards: list[float] = []
        stopped = False
        for episode in range(1, episodes + 1):
            reward, steps, info, stopped = self._run_episode(
                seed + episode, explore=False, learn=False, should_stop=should_stop)
            self.logger.log_episode(episode, reward, steps, info)
            rewards.append(reward)
            if stopped:
                break
        mean = sum(rewards) / max(len(rewards), 1)
        print(f"{'Stopped' if stopped else 'Evaluation'}: "
              f"mean reward {mean:+.2f} over {len(rewards)} episode(s)")
        return {"stopped": stopped, "episodes": len(rewards), "mean_reward": mean}

    def _run_episode(
        self, seed: int, explore: bool, learn: bool, should_stop: StopFn | None,
    ) -> tuple[float, int, dict, bool]:
        observation, info = self.env.reset(seed)
        self.agent.on_episode_start()
        total_reward = 0.0
        steps = 0
        done = False
        stopped = False
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
            if should_stop is not None and should_stop():
                stopped = True
                break
        return total_reward, steps, info, stopped
