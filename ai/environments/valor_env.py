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
    [13]    player level / 10
    [14]    xp fraction toward next level
    [15]    upgrade choice pending (0/1)
    [16:19] pending option encoding: (pool_index + 1) / upgrade_pool_size,
            0 = empty slot
    [19:59] MAX_TRACKED_ENEMIES slots of
            [present, local_x / arena_scale, local_z / arena_scale,
             distance / arena_scale, health_fraction,
             type one-hot: melee, tank, ranged]
    [59:83] MAX_TRACKED_PROJECTILES slots of incoming enemy shots within
            projectile_radius of the player:
            [present, local_x / projectile_radius, local_z / projectile_radius,
             local_vel_x / projectile_speed, local_vel_z / projectile_speed,
             distance / projectile_radius]
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from communication.godot_client import GodotClient

MAX_TRACKED_ENEMIES = 5  # must match ObservationBuilder.MAX_TRACKED_ENEMIES
ENEMY_FEATURES = 8
ENEMY_TYPE_COUNT = 3  # melee=0, tank=1, ranged=2 (Enemy.TYPE_* in Godot)
MAX_TRACKED_PROJECTILES = 4  # must match ObservationBuilder.MAX_TRACKED_PROJECTILES
PROJECTILE_FEATURES = 6
UPGRADE_OPTION_SLOTS = 3
ENEMY_SLOTS_OFFSET = 19
PROJECTILE_SLOTS_OFFSET = ENEMY_SLOTS_OFFSET + MAX_TRACKED_ENEMIES * ENEMY_FEATURES
OBS_SIZE = PROJECTILE_SLOTS_OFFSET + MAX_TRACKED_PROJECTILES * PROJECTILE_FEATURES


class ValorEnv:
    """Connects lazily on the first reset() so construction is side-effect free."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 11008,
        max_episode_steps: int = 2000,
        arena_scale: float = 28.0,
        max_speed: float = 5.0,
        upgrade_pool_size: int = 6,
        projectile_radius: float = 12.0,  # ObservationBuilder.PROJECTILE_TRACK_RADIUS
        projectile_speed: float = 20.0,   # fastest projectile scene's speed
        agent_name: str = "AI",
    ) -> None:
        self.client = GodotClient(host, port)
        self.max_episode_steps = max_episode_steps
        self.arena_scale = arena_scale
        self.max_speed = max_speed
        self.upgrade_pool_size = upgrade_pool_size
        self.projectile_radius = projectile_radius
        self.projectile_speed = projectile_speed
        self.agent_name = agent_name
        self._steps = 0
        self._connected = False

    def reset(self, seed: int = 0) -> tuple[np.ndarray, dict[str, Any]]:
        self._ensure_connected()
        response = self.client.request(
            {"type": "reset", "seed": int(seed), "agent": self.agent_name})
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
        vector[13] = player.get("level", 1) / 10.0
        vector[14] = player.get("xp_fraction", 0.0)
        upgrade = obs.get("upgrade", {})
        vector[15] = 1.0 if upgrade.get("pending") else 0.0
        options = upgrade.get("options", [])
        for slot in range(UPGRADE_OPTION_SLOTS):
            if slot < len(options) and options[slot] >= 0:
                vector[16 + slot] = (options[slot] + 1) / max(self.upgrade_pool_size, 1)
        for slot, enemy in enumerate(obs["enemies"][:MAX_TRACKED_ENEMIES]):
            base = ENEMY_SLOTS_OFFSET + slot * ENEMY_FEATURES
            vector[base] = 1.0
            vector[base + 1] = enemy["position"][0] / self.arena_scale
            vector[base + 2] = enemy["position"][2] / self.arena_scale
            vector[base + 3] = enemy["distance"] / self.arena_scale
            vector[base + 4] = enemy.get("health_fraction", 1.0)
            enemy_type = int(enemy.get("type", 0))
            if 0 <= enemy_type < ENEMY_TYPE_COUNT:
                vector[base + 5 + enemy_type] = 1.0
        for slot, projectile in enumerate(
                obs.get("projectiles", [])[:MAX_TRACKED_PROJECTILES]):
            base = PROJECTILE_SLOTS_OFFSET + slot * PROJECTILE_FEATURES
            vector[base] = 1.0
            vector[base + 1] = projectile["position"][0] / self.projectile_radius
            vector[base + 2] = projectile["position"][2] / self.projectile_radius
            vector[base + 3] = projectile["velocity"][0] / self.projectile_speed
            vector[base + 4] = projectile["velocity"][2] / self.projectile_speed
            vector[base + 5] = projectile["distance"] / self.projectile_radius
        return vector

    def __enter__(self) -> "ValorEnv":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()
