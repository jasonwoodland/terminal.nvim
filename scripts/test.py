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
SKIP = re.compile(r"^SKIP\b", re.MULTILINE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", help="test paths (default: tests/*.lua)")
    parser.add_argument("--nvim", default=os.environ.get("NVIM", "nvim"))
    parser.add_argument("--timeout", type=float, default=180, help="seconds per suite")
    parser.add_argument("--require-test", action="append", default=[], help="suite filename that must not skip")
    args = parser.parse_args()
    tests = [ROOT / name for name in args.tests] if args.tests else sorted((ROOT / "tests").glob("*.lua"))
    missing = set(args.require_test) - {test.name for test in tests}
    if missing:
        parser.error("required suites are not selected: " + ", ".join(sorted(missing)))
    failures, skipped = 0, 0
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
        skip = bool(SKIP.search(output)) and not failed
        if skip and test.name in args.require_test:
            failed, skip = True, False
            output = "Required suite skipped:\n" + output
        failures += bool(failed)
        skipped += bool(skip)
        label = "FAIL" if failed else "SKIP" if skip else "PASS"
        print(f"{label} {test.name} ({time.monotonic() - start:.2f}s)", flush=True)
        if failed:
            print("TIMEOUT" if timed_out else f"exit={process.returncode}")
            print(output, flush=True)
        elif skip:
            print(output.strip(), flush=True)
    print(f"{len(tests) - failures - skipped} passed, {skipped} skipped, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
