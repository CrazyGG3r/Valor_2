# Valor 2 — RL Training Package

Python side of the Valor 2 reinforcement learning environment. The game
(Godot) is the simulator; this package connects to it, wraps it in a
Gym-style API, and trains agents against it.

## Layout

```
ai/
├── main.py            # CLI entry point; registry of all algorithms
├── agents/            # Agent base contract + learning-free baselines
├── algorithms/        # RL implementations (DQN, PPO; SAC/A2C/DDPG planned)
├── communication/     # TCP JSON-lines protocol client
├── environments/      # ValorEnv (Gym-style) + action-space conversion
├── trainers/          # Algorithm-agnostic train/eval loop + checkpointing
├── utils/             # Replay buffer, logging, config, seeding
├── configs/           # Hyperparameter JSON files
├── weights/           # Checkpoints land here (per algorithm, per run)
├── logs/              # CSV + TensorBoard event files
└── tests/             # Pure unit tests (no Godot/torch needed)
```

## Quickstart

1. Start the simulation — either press Play on `main.tscn` in the Godot
   editor, or run headless for training speed:

   ```
   <godot.exe> --path <project-dir> --headless -- --ai-port=11008 --speed=8
   ```

   (`--speed` multiplies `Engine.time_scale`; steps stay deterministic, they
   just execute faster in real time.)

2. Install and smoke-test with the random baseline (no PyTorch needed):

   ```
   cd ai
   pip install -r requirements.txt
   python main.py --algo random --mode eval --episodes 3
   ```

3. Train:

   ```
   python main.py --algo dqn --mode train --episodes 500 --seed 42 --config configs/dqn.json
   python main.py --algo ppo --mode train --episodes 500 --seed 42 --config configs/ppo.json
   ```

4. Evaluate a checkpoint:

   ```
   python main.py --algo dqn --mode eval --episodes 10 --checkpoint weights/dqn/<run>/best.pt
   ```

Curves: `tensorboard --logdir logs` (if tensorboard is installed).

## Protocol (Godot `AIBridge` autoload, TCP 127.0.0.1:11008)

One JSON object per line, strict request/reply, single client. While a client
is connected the simulation is **lockstepped**: the SceneTree stays paused
except for the exact physics frames that execute a step (4 frames per step,
i.e. one agent action every 4 ticks at 60 Hz physics).

| Direction | Message |
|---|---|
| ← on connect | `{"type": "hello", "version": 1, "frames_per_step": 4, ...}` |
| → | `{"type": "reset", "seed": 123}` |
| → | `{"type": "step", "action": {"move": [x, y], "look": [x, y], "jump": false, "attack": false, "shoot": false, "dash": false}}` |
| ← reply to both | `{"type": "obs", "observation": {...}, "reward": 0.0, "done": false, "info": {"kills": 0, "time": 1.2, "wave": 1}}` |
| → | `{"type": "close"}` |

Action conventions: `move` x = strafe (+right), y = forward/back (+back);
`look` x = yaw rate; everything in [-1, 1]. `attack` (melee swing), `shoot`
(projectile) and `dash` (burst + i-frames) are held-button semantics: keep
them `true` to auto-repeat as fast as their cooldowns allow.

The observation dict and its flattened vector layout are documented in
`environments/valor_env.py` and must stay in sync with
`scripts/ai/observation_builder.gd`. Rewards are configured in Godot:
`configs/reward_config.tres`.

## Adding a new algorithm

1. Implement `agents.base_agent.Agent` in `algorithms/<name>.py`.
2. Add one line to `AGENT_REGISTRY` in `main.py`.

Nothing else changes — the trainer, env, logging, and checkpointing are
algorithm-agnostic.
