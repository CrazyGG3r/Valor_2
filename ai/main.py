"""Valor 2 RL entry point (scriptable CLI). For an interactive menu instead,
run `python console.py`.

Examples:
    python main.py --algo random --mode eval --episodes 3
    python main.py --algo rainbow --mode train --episodes 500 --seed 42
    python main.py --algo ppo --mode train --config configs/ppo.json
    python main.py --algo dreamer --mode eval --checkpoint weights/dreamer/best.pt

Start the Godot simulation first (editor Play, or headless for training):
    <godot.exe> --path <project> --headless -- --ai-port=11008 --speed=8
"""
from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path

import registry
from trainers.trainer import Trainer
from utils.config import set_global_seeds
from utils.run_logger import RunLogger


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train or evaluate a Valor 2 agent.")
    parser.add_argument("--algo", choices=sorted(registry.AGENT_REGISTRY), default="random")
    parser.add_argument("--mode", choices=["train", "eval"], default="train")
    parser.add_argument("--episodes", type=int, default=100)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=None, help="overrides config/env default")
    parser.add_argument("--config", type=Path, default=None, help="JSON config file")
    parser.add_argument("--checkpoint", type=Path, default=None, help="weights to load")
    parser.add_argument("--resume", action="store_true", help="continue from weights/<algo>/latest.pt")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    set_global_seeds(args.seed)
    config = registry.resolve_config(args.algo, args.config)

    env = registry.build_env(config, args.host, args.port, agent_name=args.algo)
    agent = registry.build_agent(args.algo, config, args.seed)
    if args.checkpoint is not None:
        agent.load(args.checkpoint)
        print(f"Loaded checkpoint: {args.checkpoint}")

    run_name = f"{args.algo}-{datetime.now():%Y%m%d-%H%M%S}"
    logger = RunLogger(registry.LOGS_ROOT, run_name)
    trainer = Trainer(
        env, agent, logger, registry.algo_weights_dir(args.algo),
        checkpoint_every=config.get("training", {}).get("checkpoint_every", 25))

    try:
        if args.mode == "train":
            trainer.train(episodes=args.episodes, seed=args.seed, resume=args.resume)
        else:
            trainer.evaluate(episodes=args.episodes, seed=args.seed)
    finally:
        env.close()
        logger.close()


if __name__ == "__main__":
    main()
