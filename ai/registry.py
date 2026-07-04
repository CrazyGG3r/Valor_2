"""Single source of truth for algorithms, config loading, and env/agent
construction. Both main.py (CLI) and console.py (interactive) build everything
through here, so adding an algorithm touches exactly one dict."""
from __future__ import annotations

import importlib
from pathlib import Path
from typing import Any

from environments.valor_env import OBS_SIZE, ValorEnv
from utils.config import load_config

AI_ROOT = Path(__file__).resolve().parent
WEIGHTS_ROOT = AI_ROOT / "weights"
LOGS_ROOT = AI_ROOT / "logs"
CONFIGS_ROOT = AI_ROOT / "configs"

# name -> "module:Class". Lazy import paths keep PyTorch out of runs that don't
# need it (the random baseline and the console listing work on bare Python).
AGENT_REGISTRY: dict[str, str] = {
    "random": "agents.random_agent:RandomAgent",
    "dqn": "algorithms.dqn:DQNAgent",
    "rainbow": "algorithms.rainbow:RainbowAgent",
    "ppo": "algorithms.ppo:PPOAgent",
    "dreamer": "algorithms.dreamer:DreamerAgent",
    "sac": "algorithms.planned:SACAgent",
    "a2c": "algorithms.planned:A2CAgent",
    "ddpg": "algorithms.planned:DDPGAgent",
}

# Short blurbs for the console. Keep in step with AGENT_REGISTRY.
AGENT_BLURBS: dict[str, str] = {
    "random": "Uniform-random baseline (no learning)",
    "dqn": "Deep Q-Network, discrete actions",
    "rainbow": "Rainbow: dueling + double + C51 + noisy + PER + n-step",
    "ppo": "Proximal Policy Optimization, continuous",
    "dreamer": "Model-based world-model agent (compact DreamerV3-style)",
    "sac": "Soft Actor-Critic (planned)",
    "a2c": "Advantage Actor-Critic (planned)",
    "ddpg": "Deep Deterministic Policy Gradient (planned)",
}

# Algorithms that are implemented and trainable today.
IMPLEMENTED: tuple[str, ...] = ("random", "dqn", "rainbow", "ppo", "dreamer")


def resolve_agent_class(name: str) -> type:
    module_path, class_name = AGENT_REGISTRY[name].split(":")
    return getattr(importlib.import_module(module_path), class_name)


def default_config_path(algo: str) -> Path | None:
    path = CONFIGS_ROOT / f"{algo}.json"
    return path if path.exists() else None


def resolve_config(algo: str, override: Path | None = None) -> dict[str, Any]:
    path = override or default_config_path(algo)
    return load_config(path) if path is not None else {}


def algo_weights_dir(algo: str) -> Path:
    return WEIGHTS_ROOT / algo


def build_env(config: dict[str, Any], host: str, port: int | None, agent_name: str) -> ValorEnv:
    env_config = config.get("env", {})
    return ValorEnv(
        host=host,
        port=port if port is not None else env_config.get("port", 11008),
        max_episode_steps=env_config.get("max_episode_steps", 2000),
        upgrade_pool_size=env_config.get("upgrade_pool_size", 6),
        agent_name=agent_name,
    )


def build_agent(algo: str, config: dict[str, Any], seed: int):
    agent_class = resolve_agent_class(algo)
    return agent_class(OBS_SIZE, {**config.get("agent", {}), "seed": seed})
