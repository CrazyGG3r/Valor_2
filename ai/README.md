# Valor 2 — RL Training Package

Python side of the Valor 2 reinforcement learning environment. The game
(Godot) is the simulator; this package connects to it, wraps it in a
Gym-style API, and trains agents against it.

## Layout

```
ai/
├── console.py         # Interactive shell (VEINS) — the easy way to drive it
├── main.py            # Scriptable CLI entry point
├── registry.py        # Single source of truth: algorithms + env/agent builders
├── agents/            # Agent base contract + learning-free baselines
├── algorithms/        # DQN, Rainbow, PPO, Dreamer (SAC/A2C/DDPG planned)
├── communication/     # TCP JSON-lines protocol client
├── environments/      # ValorEnv (Gym-style) + action-space conversion
├── trainers/          # Algorithm-agnostic train/eval loop + checkpointing
├── utils/             # Replay buffer, segment tree, logging, status, key poller
├── configs/           # Hyperparameter JSON files
├── weights/           # weights/<algo>/{best,latest,ep_*}.pt + status.json
├── logs/              # CSV + TensorBoard event files
└── tests/             # Pure unit tests (no Godot/torch needed)
```

## Algorithms

| name | family | notes |
|---|---|---|
| `random` | baseline | no learning; runs without PyTorch |
| `dqn` | value, discrete | vanilla Deep Q-Network over the 27-action set |
| `rainbow` | value, discrete | dueling + double + C51 + NoisyNet + PER + n-step |
| `ppo` | policy, continuous | clipped PPO with GAE |
| `dreamer` | model-based | compact DreamerV3-style world model + imagination A-C |
| `sac`/`a2c`/`ddpg` | — | planned; raise `NotImplementedError` |

## Quickstart — the console (recommended)

1. Start the Godot simulation (editor Play, or headless for speed):

   ```
   <godot.exe> --path <project-dir> --headless -- --ai-port=11008 --speed=8
   ```

   (`--speed` multiplies `Engine.time_scale`; steps stay deterministic, they
   just execute faster in real time. Drop `--headless`/`--speed` when you want
   to *watch* an agent play.)

2. Launch the shell and follow the menu:

   ```
   cd ai
   pip install -r requirements.txt
   python console.py
   ```

   VEINS lists every algorithm with its current trained level, checks whether
   Godot is reachable, and lets you **train** or **play best** per algorithm,
   view **details**, **reset** progress, or see the **leaderboard**. Press `q`
   during any session to stop and save — no Ctrl-C.

## Quickstart — the CLI (scripting)

```
python main.py --algo random  --mode eval  --episodes 3
python main.py --algo rainbow --mode train --episodes 500 --seed 42
python main.py --algo dreamer --mode train --episodes 500 --resume
python main.py --algo ppo     --mode eval  --episodes 10 --checkpoint weights/ppo/best.pt
```

Checkpoints are per-algorithm: `weights/<algo>/best.pt` (highest episode
reward ever), `latest.pt` (resume point), `status.json` (cumulative progress).
Curves: `tensorboard --logdir logs` (if tensorboard is installed).

## Protocol (Godot `AIBridge` autoload, TCP 127.0.0.1:11008)

One JSON object per line, strict request/reply, single client. While a client
is connected the simulation is **lockstepped**: the SceneTree stays paused
except for the exact physics frames that execute a step (4 frames per step,
i.e. one agent action every 4 ticks at 60 Hz physics).

| Direction | Message |
|---|---|
| ← on connect | `{"type": "hello", "version": 3, "frames_per_step": 4, ...}` |
| → | `{"type": "reset", "seed": 123, "agent": "dqn"}` |
| → | `{"type": "step", "action": {"move": [x, y], "look": [x, y], "jump": false, "attack": false, "shoot": false, "dash": false, "upgrade": 0}}` |
| ← reply to both | `{"type": "obs", "observation": {...}, "reward": 0.0, "done": false, "info": {"kills": 0, "time": 1.2, "wave": 1}}` |
| → | `{"type": "close"}` |

**Decision steps:** when the observation reports a pending upgrade choice
(`observation.upgrade.pending`), the next `step` consumes only the
`"upgrade"` field (option index 0-2) and advances zero physics frames --
the exact analog of the pause a human gets on the level-up screen. All
current agents send `upgrade: 0` (first option); learning to choose is a
future improvement.

Action conventions: `move` x = strafe (+right), y = forward/back (+back);
`look` x = yaw rate; everything in [-1, 1]. `attack` (melee swing), `shoot`
(projectile) and `dash` (burst + i-frames) are held-button semantics: keep
them `true` to auto-repeat as fast as their cooldowns allow.

The observation dict and its flattened vector layout are documented in
`environments/valor_env.py` and must stay in sync with
`scripts/ai/observation_builder.gd`. Rewards are configured in Godot:
`configs/reward_config.tres`.

## Adding a new algorithm

1. Implement `agents.base_agent.Agent` in `algorithms/<name>.py` (recurrent
   agents set `is_recurrent = True` and reset state in `on_episode_start`).
2. Add one line to `AGENT_REGISTRY` (and a blurb) in `registry.py`; list it in
   `IMPLEMENTED`.

Nothing else changes — the trainer, env, logging, checkpointing, the CLI, and
the console all read the registry.

## A note on Dreamer

Dreamer here is a **compact, DreamerV3-inspired** implementation tuned for
vector observations (MLP encoder/decoder, Gaussian latents). It keeps the core
ideas — RSSM world model, KL-balanced representation learning, and actor-critic
learning on lambda-returns in imagination — but omits heavier V3 machinery
(discrete latents, symlog/two-hot heads, return normalization). It is the most
experimental agent in the package; expect to tune it.
