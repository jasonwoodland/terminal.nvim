"""Query terminal default colors and capture all replies, including duplicates."""
import os
from pathlib import Path
import select
import sys
import time
import tty

tty.setraw(sys.stdin.fileno())
terminator = b"\x07" if sys.argv[2] == "bel" else b"\x1b\\"
os.write(sys.stdout.fileno(), b"\x1b]10;?" + terminator + b"\x1b]11;?" + terminator)
received = bytearray()
deadline = time.monotonic() + 0.5
while (remaining := deadline - time.monotonic()) > 0:
    if select.select([sys.stdin], [], [], remaining)[0]:
        received.extend(os.read(sys.stdin.fileno(), 4096))
Path(sys.argv[1]).write_bytes(received)
