"""JSON-lines TCP client for the Godot AIBridge autoload (scripts/ai/ai_bridge.gd)."""
from __future__ import annotations

import json
import socket
import time
from typing import Any


class GodotConnectionError(RuntimeError):
    """Raised when the Godot simulation cannot be reached or hangs up."""


class GodotClient:
    """Blocking, single-connection protocol client. One JSON object per line."""

    def __init__(self, host: str = "127.0.0.1", port: int = 11008, timeout: float = 60.0) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self.hello: dict[str, Any] | None = None
        self._sock: socket.socket | None = None
        self._file = None

    def connect(self, retries: int = 20, retry_delay: float = 0.5) -> dict[str, Any]:
        """Connect and return the server hello. Retries while Godot boots."""
        last_error: Exception | None = None
        for _ in range(retries):
            try:
                sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
            except OSError as error:
                last_error = error
                time.sleep(retry_delay)
                continue
            sock.settimeout(self.timeout)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self._sock = sock
            self._file = sock.makefile("r", encoding="utf-8", newline="\n")
            self.hello = self.receive()
            if self.hello.get("type") != "hello":
                raise GodotConnectionError(f"expected hello, got: {self.hello}")
            return self.hello
        raise GodotConnectionError(
            f"could not reach Godot at {self.host}:{self.port} - "
            f"is the game running? ({last_error})"
        )

    def send(self, message: dict[str, Any]) -> None:
        if self._sock is None:
            raise GodotConnectionError("not connected")
        self._sock.sendall((json.dumps(message) + "\n").encode("utf-8"))

    def receive(self) -> dict[str, Any]:
        if self._file is None:
            raise GodotConnectionError("not connected")
        line = self._file.readline()
        if not line:
            raise GodotConnectionError("Godot closed the connection")
        return json.loads(line)

    def request(self, message: dict[str, Any]) -> dict[str, Any]:
        """Send one message and return its reply, raising on protocol errors."""
        self.send(message)
        response = self.receive()
        if response.get("type") == "error":
            raise GodotConnectionError(f"bridge error: {response.get('message')}")
        return response

    def close(self) -> None:
        if self._sock is not None:
            try:
                self.send({"type": "close"})
            except Exception:
                pass
            self._sock.close()
        self._sock = None
        self._file = None

    def __enter__(self) -> "GodotClient":
        self.connect()
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()
