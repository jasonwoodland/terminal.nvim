"""Exercise :restart through Neovim's real TUI and RPC CLI, without pynvim."""
import collections
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

nvim, root = sys.argv[1:]
tail = collections.deque(maxlen=64)
servers = set()

with tempfile.TemporaryDirectory(prefix="terminal-restart-") as directory:
    base = Path(directory)
    address = str(base / "nvim.sock")
    init = base / "init.lua"
    init.write_text(
        "vim.opt.runtimepath:prepend(vim.env.TERMINAL_RESTART_ROOT)\n"
        "vim.env.SHELL = '/bin/sh'\n"
        "vim.o.swapfile = false\n"
        "require('terminal').setup({ keys = false, set_buffer_name = false, float_zoom_hide_cmdline = true, "
        "float = { padding = { x = 2, y = 2 } } })\n"
    )
    one, two = base / "one.txt", base / "two.txt"
    one.write_text("one\ntwo\nthree\n")
    two.write_text("alpha\nbeta\ngamma\n")
    pid, master = pty.fork()
    if pid == 0:
        env = dict(os.environ, TERM="xterm-256color", TERMINAL_RESTART_ROOT=root)
        env.pop("NVIM", None)
        os.execve(nvim, [nvim, "--clean", "-u", str(init), "--listen", address], env)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 42, 120, 0, 0))
    stop = threading.Event()

    def drain():
        previous = b""
        while not stop.is_set():
            try:
                if select.select([master], [], [], 0.1)[0]:
                    data = os.read(master, 65536)
                    if not data:
                        return
                    tail.append(data)
                    combined = previous + data
                    for pattern, reply in (
                        (b"\x1b]11;\\?", b"\x1b]11;rgb:0000/0000/0000\x1b\\"),
                        (b"\x1b\\[5n", b"\x1b[0n"),
                    ):
                        for match in re.finditer(pattern, combined):
                            if match.end() > len(previous):
                                os.write(master, reply)
                    previous = combined[-32:]
            except OSError:
                return

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()

    def query(code):
        payload = "vim.json.encode((function() " + code + " end)())"
        expression = "luaeval('" + payload.replace("'", "''") + "')"
        result = subprocess.run(
            [nvim, "--server", address, "--remote-expr", expression],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3,
        )
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors="replace"))
        return json.loads(result.stdout.decode())

    def wait_for(callback, message):
        deadline = time.monotonic() + 12
        last = None
        while time.monotonic() < deadline:
            try:
                last = callback()
                if last:
                    return last
            except (RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
                last = str(exc)
            time.sleep(0.05)
        raise AssertionError(f"{message}: {last!r}")

    def state():
        value = query(
            "return { pid = vim.fn.getpid(), tabs = #vim.api.nvim_list_tabpages(), "
            "panes = #require('terminal').list(), file = vim.api.nvim_buf_get_name(0), "
            "row = vim.api.nvim_win_get_cursor(0)[1], tab = vim.fn.tabpagenr(), "
            "reason = vim.v.startreason, mode = vim.api.nvim_get_mode().mode, "
            "title = vim.b.terminal_custom_name or '', zoom = not not vim.t.term_zoom, cmdheight = vim.o.cmdheight }"
        )
        servers.add(value["pid"])
        return value

    try:
        wait_for(lambda: Path(address).exists() and state(), "TUI server starts")
        query(
            "local t = require('terminal'); vim.cmd.edit(" + json.dumps(str(one)) + "); "
            "t.new({ name = 'Shell' }); t.vsplit({ name = 'Tests' }); "
            "t.new({ name = 'Database' }); t.go_to(1); t.float_toggle(); assert(t.resize({ width = '80%', height = '75%' })); "
            "vim.cmd('tabnew'); vim.cmd.edit(" + json.dumps(str(two)) + "); "
            "local editor = vim.api.nvim_get_current_win(); t.new({ name = 'Server' }); assert(t.resize({ height = '50%' })); "
            "vim.api.nvim_set_current_win(editor); vim.api.nvim_win_set_cursor(editor, { 2, 0 }); return true"
        )
        initial = state()
        assert initial["tabs"] == 2 and initial["panes"] == 4
        # Change hidden and visible shells independently, without OSC integration.
        cwd_targets = {}
        for title in ("Shell", "Tests", "Database", "Server"):
            target = base / (title + " working directory")
            target.mkdir()
            cwd_targets[title] = str(target.resolve())
        query(
            "local targets = vim.json.decode(" + json.dumps(json.dumps(cwd_targets)) + "); "
            "for _, item in ipairs(require('terminal').list()) do "
            "local dir = targets[item.title]; vim.fn.chansend(vim.b[item.bufnr].terminal_job_id, "
            "'cd ' .. vim.fn.shellescape(dir) .. '; touch ready\\n') end; return true"
        )
        wait_for(lambda: all((Path(path) / "ready").exists() for path in cwd_targets.values()),
                 "all shells finish cd before restart")
        subprocess.run([nvim, "--server", address, "--remote-send", "<C-\\><C-n><Esc>:restart<CR>"], check=True, timeout=3)

        def restored():
            value = state()
            return value if value["pid"] != initial["pid"] and value["panes"] == 4 else None

        after = wait_for(restored, ":restart restores terminal workspaces")
        assert after["tabs"] == 2 and after["tab"] == 2 and after["row"] == 2 and after["mode"] == "n", after
        assert Path(after["file"]).resolve() == two.resolve() and after["reason"] == "restart", after
        names = query("return vim.tbl_map(function(item) return item.title end, require('terminal').list())")
        assert sorted(names) == ["Database", "Server", "Shell", "Tests"], names
        restored_cwds = query(
            "local result = {}; for _, item in ipairs(require('terminal').list()) do "
            "result[item.title] = require('terminal.cwd').resolve(item.bufnr) end; return result"
        )
        assert restored_cwds == cwd_targets, restored_cwds
        assert query("local tabs = vim.api.nvim_list_tabpages(); return "
                     "vim.deep_equal(vim.t[tabs[1]].term_float_size, { width = '80%', height = '75%' }) "
                     "and vim.t[tabs[2]].term_drawer_size == '50%'")

        query("for _, item in ipairs(require('terminal').list()) do if item.title == 'Server' then "
              "assert(require('terminal').focus(item.bufnr)); require('terminal').zoom(); break end end; return true")
        wait_for(lambda: state()["mode"] == "t", "selected terminal enters input mode")
        try:
            query("vim.schedule(function() vim.cmd('restart') end); return true")
        except (RuntimeError, ValueError, subprocess.TimeoutExpired):
            pass  # The old RPC connection can close before its response arrives.

        def terminal_restored():
            value = state()
            return value if value["pid"] != after["pid"] and value["panes"] == 4 and value["mode"] == "t" else None

        terminal_after = wait_for(terminal_restored, "restart preserves focused terminal input mode")
        assert terminal_after["tabs"] == 2 and terminal_after["title"] == "Server" and terminal_after["zoom"] \
            and terminal_after["cmdheight"] == 0, terminal_after
        after = terminal_after

        subprocess.run([nvim, "--server", address, "--remote-send", "<C-\\><C-n><Esc>:restart!<CR>"], check=True, timeout=3)
        def fresh():
            value = state()
            return value if value["pid"] != after["pid"] else None

        discarded = wait_for(fresh, ":restart! starts a fresh server")
        assert discarded["panes"] == 0 and discarded["tabs"] == 1 and discarded["reason"] == "restart!" \
            and discarded["cmdheight"] > 0, discarded
        print("Native :restart and :restart! TUI regressions passed")
    except Exception:
        sys.stderr.write(b"".join(tail)[-4000:].decode(errors="replace") + "\n")
        raise
    finally:
        try:
            query("vim.cmd('qall!'); return true")
        except Exception:
            pass
        stop.set()
        reader.join(timeout=1)
        os.close(master)
        for server in servers:
            try:
                os.kill(server, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
