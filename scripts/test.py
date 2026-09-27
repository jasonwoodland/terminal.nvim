#!/usr/bin/env python3
"""Run isolated Neovim suites, failing on timeouts and asynchronous Lua errors."""
import argparse
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
ERROR = re.compile(r"FAIL -|stack traceback:|Error executing|E5113:|E5108:")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", help="test paths (default: tests/*.lua)")
    parser.add_argument("--nvim", default=os.environ.get("NVIM", "nvim"))
    parser.add_argument("--timeout", type=float, default=180, help="seconds per suite")
    args = parser.parse_args()
    tests = [ROOT / name for name in args.tests] if args.tests else sorted((ROOT / "tests").glob("*.lua"))
    failures = 0
    for test in tests:
        start = time.monotonic()
        process = subprocess.Popen(
            [args.nvim, "--clean", "--headless", "-l", str(test)], cwd=ROOT,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
        )
        timed_out = False
        try:
            output, _ = process.communicate(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
        output = output.decode("utf-8", errors="replace")
        failed = timed_out or process.returncode != 0 or ERROR.search(output)
        failures += bool(failed)
        print(f"{'FAIL' if failed else 'PASS'} {test.name} ({time.monotonic() - start:.2f}s)", flush=True)
        if failed:
            print("TIMEOUT" if timed_out else f"exit={process.returncode}")
            print(output, flush=True)
    print(f"{len(tests) - failures}/{len(tests)} suites passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
