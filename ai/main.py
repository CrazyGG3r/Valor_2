"""Valor 2 RL entry point. Run from the ai/ directory.

Examples:
    python main.py --algo random --mode eval --episodes 3
    python main.py --algo dqn --mode train --episodes 500 --seed 42
    python main.py --algo ppo --mode train --config configs/ppo.json
    python main.py --algo dqn --mode eval --checkpoint weights/dqn/<run>/best.pt

Start the Godot simulation first (editor Play, or headless for training):
    <godot.exe> --path <project> --headless -- --ai-port=11008 --speed=8
"""
from __future__ import annotations

import argparse
import importlib
from datetime import datetime
from pathlib import Path

from environments.valor_env import OBS_SIZE, ValorEnv
from trainers.trainer import Trainer
from utils.config import load_config, set_global_seeds
from utils.run_logger import RunLogger

AI_ROOT = Path(__file__).resolve().parent

# Every algorithm, mapped as "module:Class". Lazy import paths (instead of
# top-of-file imports) keep optional dependencies like PyTorch out of runs
# that don't need them -- `--algo random` works on a bare Python install.
AGENT_REGISTRY: dict[str, str] = {
    "random": "agents.random_agent:RandomAgent",
    "dqn": "algorithms.dqn:DQNAgent",
    "ppo": "algorithms.ppo:PPOAgent",
    "sac": "algorithms.planned:SACAgent",
    "a2c": "algorithms.planned:A2CAgent",
    "ddpg": "algorithms.planned:DDPGAgent",
}


def resolve_agent_class(name: str) -> type:
    module_path, class_name = AGENT_REGISTRY[name].split(":")
    return getattr(importlib.import_module(module_path), class_name)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train or evaluate a Valor 2 agent.")
    parser.add_argument("--algo", choices=sorted(AGENT_REGISTRY), default="random")
    parser.add_argument("--mode", choices=["train", "eval"], default="train")
    parser.add_argument("--episodes", type=int, default=100)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=None, help="overrides config/env default")
    parser.add_argument("--config", type=Path, default=None, help="JSON config file")
    parser.add_argument("--checkpoint", type=Path, default=None, help="weights to load")
    parser.add_argument("--run-name", default=None, help="defaults to a timestamp")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = load_config(args.config) if args.config else {}
    set_global_seeds(args.seed)

    env_config = config.get("env", {})
    env = ValorEnv(
        host=args.host,
        port=args.port if args.port is not None else env_config.get("port", 11008),
        max_episode_steps=env_config.get("max_episode_steps", 2000),
    )

    agent_class = resolve_agent_class(args.algo)
    agent = agent_class(OBS_SIZE, {**config.get("agent", {}), "seed": args.seed})
    if args.checkpoint is not None:
        agent.load(args.checkpoint)
        print(f"Loaded checkpoint: {args.checkpoint}")

    run_name = args.run_name or datetime.now().strftime("%Y%m%d-%H%M%S")
    logger = RunLogger(AI_ROOT / "logs", f"{args.algo}-{run_name}")
    trainer = Trainer(
        env,
        agent,
        logger,
        run_name=run_name,
        weights_root=AI_ROOT / "weights",
        checkpoint_every=config.get("training", {}).get("checkpoint_every", 25),
    )

    try:
        if args.mode == "train":
            trainer.train(episodes=args.episodes, seed=args.seed)
        else:
            trainer.evaluate(episodes=args.episodes, seed=args.seed)
    finally:
        env.close()
        logger.close()


if __name__ == "__main__":
    main()
