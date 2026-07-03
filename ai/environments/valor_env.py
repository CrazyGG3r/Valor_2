"""Gymnasium-style environment wrapping the live Godot simulation.

    reset(seed)  -> (observation, info)
    step(action) -> (observation, reward, terminated, truncated, info)

Actions are wire dicts; build them with environments.action_space helpers.

Observation vector layout (float32, OBS_SIZE) -- keep in sync with
scripts/ai/observation_builder.gd:
    [0]     health fraction
    [1:3]   player position x, z (/ arena_scale)
    [3:5]   player local velocity x, z (/ max_speed)
    [5:7]   sin(yaw), cos(yaw)
    [7]     wave index / 10
    [8]     episode time / 60 s
    [9]     live enemy count / 10
    [10:13] cooldown fractions: melee, shoot, dash (0 = ready)
    [13:]   MAX_TRACKED_ENEMIES slots of
            [present, local_x / arena_scale, local_z / arena_scale,
             distance / arena_scale]
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from communication.godot_client import GodotClient

MAX_TRACKED_ENEMIES = 5  # must match ObservationBuilder.MAX_TRACKED_ENEMIES
ENEMY_FEATURES = 4
ENEMY_SLOTS_OFFSET = 13
OBS_SIZE = ENEMY_SLOTS_OFFSET + MAX_TRACKED_ENEMIES * ENEMY_FEATURES


class ValorEnv:
    """Connects lazily on the first reset() so construction is side-effect free."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 11008,
        max_episode_steps: int = 2000,
        arena_scale: float = 20.0,
        max_speed: float = 5.0,
    ) -> None:
        self.client = GodotClient(host, port)
        self.max_episode_steps = max_episode_steps
        self.arena_scale = arena_scale
        self.max_speed = max_speed
        self._steps = 0
        self._connected = False

    def reset(self, seed: int = 0) -> tuple[np.ndarray, dict[str, Any]]:
        self._ensure_connected()
        response = self.client.request({"type": "reset", "seed": int(seed)})
        self._steps = 0
        return self._flatten(response["observation"]), response.get("info", {})

    def step(self, action: dict) -> tuple[np.ndarray, float, bool, bool, dict[str, Any]]:
        response = self.client.request({"type": "step", "action": action})
        self._steps += 1
        observation = self._flatten(response["observation"])
        reward = float(response["reward"])
        terminated = bool(response["done"])
        truncated = self._steps >= self.max_episode_steps and not terminated
        return observation, reward, terminated, truncated, response.get("info", {})

    def close(self) -> None:
        if self._connected:
            self.client.close()
            self._connected = False

    def _ensure_connected(self) -> None:
        if not self._connected:
            self.client.connect()
            self._connected = True

    def _flatten(self, obs: dict) -> np.ndarray:
        player = obs["player"]
        vector = np.zeros(OBS_SIZE, dtype=np.float32)
        vector[0] = player["health"] / max(player["max_health"], 1.0)
        vector[1] = player["position"][0] / self.arena_scale
        vector[2] = player["position"][2] / self.arena_scale
        vector[3] = player["velocity_local"][0] / self.max_speed
        vector[4] = player["velocity_local"][2] / self.max_speed
        vector[5] = math.sin(player["yaw"])
        vector[6] = math.cos(player["yaw"])
        vector[7] = obs["wave"] / 10.0
        vector[8] = obs["time"] / 60.0
        vector[9] = obs["enemy_count"] / 10.0
        cooldowns = player.get("cooldowns", {})
        vector[10] = cooldowns.get("melee", 0.0)
        vector[11] = cooldowns.get("shoot", 0.0)
        vector[12] = cooldowns.get("dash", 0.0)
        for slot, enemy in enumerate(obs["enemies"][:MAX_TRACKED_ENEMIES]):
            base = ENEMY_SLOTS_OFFSET + slot * ENEMY_FEATURES
            vector[base] = 1.0
            vector[base + 1] = enemy["position"][0] / self.arena_scale
            vector[base + 2] = enemy["position"][2] / self.arena_scale
            vector[base + 3] = enemy["distance"] / self.arena_scale
        return vector

    def __enter__(self) -> "ValorEnv":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()
