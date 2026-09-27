"""PTY input probe: disable line processing, capture exact bytes, stay alive."""
import os
import sys
import tty

tty.setraw(sys.stdin.fileno())
if sys.argv[2] == "bracketed":
    os.write(sys.stdout.fileno(), b"\x1b[?2004h")
os.write(sys.stdout.fileno(), b"READER_READY\r\n")
with open(sys.argv[1], "ab", buffering=0) as output:
    while True:
        data = os.read(sys.stdin.fileno(), 4096)
        if not data:
            break
        output.write(data)
