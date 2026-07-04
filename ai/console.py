"""VEINS -- the Valor 2 Environment & Intelligence Navigation Shell.

An interactive console for training and playing RL agents against the running
Godot simulation, so you never have to remember the CLI flags. Run it from the
ai/ directory:

    python console.py

Stop a training or play session at any time by pressing 'q' -- it saves and
returns to the menu cleanly (no Ctrl-C needed).
"""
from __future__ import annotations

import socket
import os
from datetime import datetime
from pathlib import Path

import registry
from trainers.trainer import Trainer
from utils.key_poller import KeyPoller
from utils.run_logger import RunLogger
from utils.status import describe_level, load_status

BANNER = r"""
 ____   ____ ___________ _____.___.  _______   
\   \ /   / \_   _____/ \__  |   |  \      \  
 \   Y   /   |    __)_   /   |   |  /   |   \ 
  \     /    |        \  \____   | /    |    \
   \___/    /_______  /  / ______| \____|__  /
                    \/   \/                \/ 

     Valor 2 - Environment & Intelligence Navigation Shell
"""

SETTINGS_PATH = registry.AI_ROOT / "console_settings.json"


class Console:
    @staticmethod
    def _clear() -> None:
        os.system("cls" if os.name == "nt" else "clear")

    def __init__(self) -> None:
        self.host = "127.0.0.1"
        self.port = 11008
        self._load_settings()

    # --- persistence --------------------------------------------------------

    def _load_settings(self) -> None:
        if SETTINGS_PATH.exists():
            import json
            try:
                data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
                self.host = data.get("host", self.host)
                self.port = int(data.get("port", self.port))
            except (ValueError, OSError):
                pass

    def _save_settings(self) -> None:
        import json
        SETTINGS_PATH.write_text(
            json.dumps({"host": self.host, "port": self.port}, indent=2), encoding="utf-8")

    # --- godot probe --------------------------------------------------------

    def _godot_reachable(self) -> bool:
        try:
            with socket.create_connection((self.host, self.port), timeout=0.4):
                return True
        except OSError:
            return False

    # --- rendering ----------------------------------------------------------

    def _print_home(self) -> None:
        self._clear()
        print(BANNER)
        online = self._godot_reachable()
        status_text = "ONLINE" if online else "OFFLINE (start the Godot game first)"
        print(f"  Godot @ {self.host}:{self.port} ... {status_text}\n")
        print("  Algorithms")
        print("  " + "-" * 66)
        print(f"  {'#':>2}  {'name':<9}{'status':<22}{'description'}")
        print("  " + "-" * 66)
        for i, algo in enumerate(registry.IMPLEMENTED, start=1):
            level = describe_level(load_status(registry.algo_weights_dir(algo)))
            blurb = registry.AGENT_BLURBS.get(algo, "")
            print(f"  {i:>2}  {algo:<9}{level:<22}{blurb[:30]}")
        planned = [a for a in registry.AGENT_REGISTRY if a not in registry.IMPLEMENTED]
        print(f"\n  Planned (not yet trainable): {', '.join(planned)}")
        print("\n  [1-{n}] select algorithm   [L] leaderboard   "
              "[S] settings   [R] refresh   [Q] quit"
              .format(n=len(registry.IMPLEMENTED)))

    def _print_leaderboard(self) -> None:
        self._clear()
        rows = []
        for algo in registry.IMPLEMENTED:
            status = load_status(registry.algo_weights_dir(algo))
            rows.append((status.get("best_reward"), algo, status))
        rows.sort(key=lambda r: (r[0] is None, -(r[0] or 0.0)))
        print("\n  Leaderboard (by best episode reward)")
        print("  " + "-" * 60)
        print(f"  {'rank':<6}{'algo':<10}{'best':<12}{'episodes':<10}{'updated'}")
        print("  " + "-" * 60)
        for rank, (best, algo, status) in enumerate(rows, start=1):
            best_text = f"{best:+.2f}" if best is not None else "-"
            updated = status.get("updated_at") or "-"
            print(f"  {rank:<6}{algo:<10}{best_text:<12}"
                  f"{status.get('episodes_trained', 0):<10}{updated}")
        input("\n  Press Enter to return...")

    # --- prompts ------------------------------------------------------------

    @staticmethod
    def _ask_int(prompt: str, default: int) -> int:
        raw = input(f"  {prompt} [{default}]: ").strip()
        if not raw:
            return default
        try:
            return int(raw)
        except ValueError:
            print("  Not a number, using default.")
            return default

    @staticmethod
    def _ask_choice(prompt: str, choices: str) -> str:
        return input(f"  {prompt} ({choices}): ").strip().lower()

    # --- actions ------------------------------------------------------------

    def _algorithm_menu(self, algo: str) -> None:
        self._clear()
        while True:
            status = load_status(registry.algo_weights_dir(algo))
            print(f"\n  == {algo.upper()} ==  {describe_level(status)}")
            print(f"     {registry.AGENT_BLURBS.get(algo, '')}")
            has_best = (registry.algo_weights_dir(algo) / "best.pt").exists()
            print("     [T] train    [P] play best{}    [D] details    "
                  "[X] reset    [B] back"
                  .format("" if has_best else " (none yet)"))
            choice = self._ask_choice("choose", "T/P/D/X/B")
            if choice == "t":
                self._train(algo)
            elif choice == "p":
                self._play(algo, has_best)
            elif choice == "d":
                self._details(algo)
            elif choice == "x":
                self._reset(algo)
            elif choice == "b":
                return

    def _train(self, algo: str) -> None:
        self._clear()
        if not self._require_godot():
            return
        episodes = self._ask_int("episodes to train", 200)
        seed = self._ask_int("random seed", 0)
        resume = (registry.algo_weights_dir(algo) / "latest.pt").exists() and \
            self._ask_choice("resume from latest checkpoint?", "y/N") == "y"
        print(f"\n  Training {algo} for {episodes} episodes. Press 'q' to stop and save.\n")
        self._run_session(algo, seed, train=True, episodes=episodes, resume=resume)

    def _play(self, algo: str, has_best: bool) -> None:
        self._clear()
        if not self._require_godot():
            return
        if not has_best:
            if self._ask_choice("No trained weights. Play untrained anyway?", "y/N") != "y":
                return
        episodes = self._ask_int("episodes to play", 3)
        print(f"\n  Playing {algo} (best weights, no exploration). "
              f"Press 'q' to stop.\n")
        self._run_session(algo, seed=10_000, train=False, episodes=episodes,
                          load_best=has_best)

    def _run_session(self, algo: str, seed: int, train: bool, episodes: int,
                     resume: bool = False, load_best: bool = False) -> None:
        try:
            config = registry.resolve_config(algo)
            env = registry.build_env(config, self.host, self.port, agent_name=algo)
            agent = registry.build_agent(algo, config, seed)
        except ImportError as error:
            print(f"\n  {error}\n  Install PyTorch to run this algorithm.\n")
            return
        except Exception as error:  # noqa: BLE001 - surface any build error to the user
            print(f"\n  Could not build {algo}: {error}\n")
            return

        algo_dir = registry.algo_weights_dir(algo)
        if load_best:
            agent.load(algo_dir / "best.pt")
        run_name = f"{algo}-{'train' if train else 'play'}-{datetime.now():%Y%m%d-%H%M%S}"
        logger = RunLogger(registry.LOGS_ROOT, run_name)
        trainer = Trainer(env, agent, logger, algo_dir,
                          checkpoint_every=config.get("training", {}).get("checkpoint_every", 25))
        try:
            with KeyPoller() as poller:
                def should_stop() -> bool:
                    key = poller.poll()
                    return key is not None and key.lower() in ("q", "\x1b")
                if train:
                    trainer.train(episodes, seed=seed, resume=resume, should_stop=should_stop)
                else:
                    trainer.evaluate(episodes, seed=seed, should_stop=should_stop)
        except Exception as error:  # noqa: BLE001 - keep the console alive
            print(f"\n  Session ended with an error: {error}")
        finally:
            env.close()
            logger.close()
        input("\n  Press Enter to return...")

    def _details(self, algo: str) -> None:
        self._clear()
        algo_dir = registry.algo_weights_dir(algo)
        status = load_status(algo_dir)
        print(f"\n  Details for {algo}")
        print("  " + "-" * 40)
        for key, value in status.items():
            print(f"  {key:<18}: {value}")
        print("  checkpoints:")
        if algo_dir.exists():
            checkpoints = sorted(algo_dir.glob("*.pt"))
            for checkpoint in checkpoints:
                size_kb = checkpoint.stat().st_size / 1024
                print(f"    {checkpoint.name:<16} {size_kb:8.1f} KB")
            if not checkpoints:
                print("    (none)")
        else:
            print("    (none)")
        input("\n  Press Enter to return...")

    def _reset(self, algo: str) -> None:
        self._clear()
        algo_dir = registry.algo_weights_dir(algo)
        if not algo_dir.exists():
            print("  Nothing to reset.")
            return
        if self._ask_choice(f"Delete ALL checkpoints/progress for {algo}?", "y/N") != "y":
            return
        for path in algo_dir.glob("*"):
            path.unlink()
        print(f"  {algo} reset to untrained.")

    def _settings(self) -> None:
        self._clear()
        print(f"\n  Current: host={self.host} port={self.port}")
        host = input(f"  host [{self.host}]: ").strip()
        if host:
            self.host = host
        self.port = self._ask_int("port", self.port)
        self._save_settings()
        print("  Saved.")

    def _require_godot(self) -> bool:
        if self._godot_reachable():
            return True
        print("\n  Godot is not reachable. Start the game first, e.g.:")
        print("    <godot.exe> --path <project> -- --ai-port=%d" % self.port)
        print("  (add --headless --speed=8 for fast training).\n")
        return False

    # --- loop ---------------------------------------------------------------

    def run(self) -> None:
        while True:
            self._print_home()
            choice = input("\n  > ").strip().lower()
            if choice in ("q", "quit", "exit"):
                print("  Goodbye.")
                return
            if choice in ("r", ""):
                continue
            if choice == "l":
                self._print_leaderboard()
                continue
            if choice == "s":
                self._settings()
                continue
            if choice.isdigit() and 1 <= int(choice) <= len(registry.IMPLEMENTED):
                self._algorithm_menu(registry.IMPLEMENTED[int(choice) - 1])
                continue
            print("  Unrecognized option.")


if __name__ == "__main__":
    try:
        Console().run()
    except (KeyboardInterrupt, EOFError):
        print("\n  Interrupted. Goodbye.")
