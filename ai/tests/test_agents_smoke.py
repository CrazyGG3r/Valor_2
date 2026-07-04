"""Smoke test for the learning agents: construct each, run a handful of
select_action/observe/update cycles on synthetic data, and round-trip save/load.

Needs no Godot (synthetic observations) but DOES need PyTorch, so it skips
cleanly when torch is absent. Overrides configs to tiny sizes so it runs fast.
Run directly: `python tests/test_agents_smoke.py`.
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np

try:
    import torch  # noqa: F401
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False

from environments.valor_env import OBS_SIZE

TINY = {
    "rainbow": {"warmup_steps": 8, "batch_size": 8, "buffer_size": 64,
                "target_update_every": 5, "atoms": 11, "hidden_size": 32, "n_step": 3},
    "dqn": {"warmup_steps": 8, "batch_size": 8, "buffer_size": 64, "hidden_sizes": [32, 32]},
    "ppo": {"rollout_steps": 32, "minibatch_size": 8, "update_epochs": 2, "hidden_sizes": [32, 32]},
    "dreamer": {"warmup_episodes": 1, "seq_len": 8, "batch_size": 2, "horizon": 4,
                "deter": 32, "stoch": 8, "hidden": 32, "embed": 32, "train_every": 1, "capacity": 500},
}


def _fake_obs() -> np.ndarray:
    return np.random.default_rng().standard_normal(OBS_SIZE).astype(np.float32)


def _run_agent(algo: str) -> None:
    from registry import build_agent
    agent = build_agent(algo, {"agent": TINY[algo]}, seed=0)
    saw_update = False
    for episode in range(3):
        agent.on_episode_start()
        obs = _fake_obs()
        for step in range(30):
            action = agent.select_action(obs, explore=True)
            assert set(action) >= {"move", "look"}, f"{algo}: malformed action {action}"
            next_obs = _fake_obs()
            terminated = step == 29
            agent.observe(obs, action, np.random.uniform(-1, 1), next_obs, terminated)
            metrics = agent.update()
            if metrics:
                saw_update = True
            obs = next_obs
    # An eval (no-explore) action must also work.
    agent.select_action(_fake_obs(), explore=False)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "chk.pt"
        agent.save(path)
        agent.load(path)
    print(f"  {algo}: ok (update fired: {saw_update})")


def main() -> None:
    if not HAS_TORCH:
        print("test_agents_smoke: PyTorch not installed, skipping (pip install torch to run).")
        return
    print("Smoke-testing learning agents:")
    for algo in ("dqn", "rainbow", "ppo", "dreamer"):
        _run_agent(algo)
    print("agent smoke tests passed")


if __name__ == "__main__":
    main()
