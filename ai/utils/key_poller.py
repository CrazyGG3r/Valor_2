"""Non-blocking single-key polling, so a training loop can be stopped by a
keypress without SIGINT/Ctrl-C. Windows uses msvcrt; POSIX uses termios cbreak.

If stdin is not an interactive terminal (piped, redirected), it degrades to a
no-op poller that never reports a key.
"""
from __future__ import annotations

import os
import sys


class KeyPoller:
    def __enter__(self) -> "KeyPoller":
        self._active = sys.stdin is not None and sys.stdin.isatty()
        if not self._active:
            return self
        if os.name == "nt":
            import msvcrt
            self._msvcrt = msvcrt
        else:
            import termios
            import tty
            self._termios = termios
            self._fd = sys.stdin.fileno()
            self._old = termios.tcgetattr(self._fd)
            tty.setcbreak(self._fd)
        return self

    def __exit__(self, *_exc: object) -> None:
        if self._active and os.name != "nt":
            self._termios.tcsetattr(self._fd, self._termios.TCSADRAIN, self._old)

    def poll(self) -> str | None:
        """Return one buffered character, or None if no key is waiting."""
        if not self._active:
            return None
        if os.name == "nt":
            if self._msvcrt.kbhit():
                return self._msvcrt.getwch()
            return None
        import select
        ready, _, _ = select.select([sys.stdin], [], [], 0)
        if ready:
            return sys.stdin.read(1)
        return None
