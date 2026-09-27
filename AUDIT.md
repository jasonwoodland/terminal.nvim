# Implementation audit — 2026-09-27

Reviewed all 21 Lua modules, README, help, and the existing regression suite.
The starting revision was `5518e1c`. Neovim verification used the local checkout
at `../../neovim/neovim`, revision `521edde`, and the matching installed
`v0.13.0-dev-1738+g521edde` executable. Selected compatibility contracts were
also checked in the local `v0.11.0` source tag. This is not a runtime certification
of every supported Neovim version or terminal emulator.

## Changes made

Each fix has a focused regression suite in addition to the existing smoke suite.

| Commit | Change | Regression |
| --- | --- | --- |
| `0ac54f7` | Restore OSC terminators; distinguish progress from notifications beginning with “4” | `tests/osc.lua` |
| `8342820` | Preserve selected entry when filtering tabs; route terminal exits to their owning Vim tab; defer background rebuilds until entry | `tests/lifecycle.lua` |
| `4e64a73` | Preserve explicit count 1 and counts in native `<C-w>` fallbacks | `tests/keymaps.lua` |
| `53b18b7` | Centralize float defaults, merge partial padding, respect hidden zoom tabline, fix nested drag growth direction | `tests/layout.lua` |
| `8ae7fee` | Save geometry with tab state; reuse windows only for matching geometry; preserve saved state after a failed swap | `tests/switching.lua` |

Before the switching fix, a pane saved at width 15 reopened at the other tab's
width 40. Both tab geometries now survive the round trip, while matching layouts
still reuse their windows. Centralizing size capture also removes repeated
`save_layout_sizes()` calls from pane and public API operations.

README/help now describe the supported command subset and intentional layout
differences, correct Vim-tab mappings and zoom-toggle behavior, document auxiliary
job commands, narrow border/key-list support, and describe actual digraph fallback.

## Remaining findings, in priority order

### High: nested minimum sizes and failed window construction

[frame.rescale](lua/terminal/frame.lua) reserves one cell for each remaining
child rather than that child's recursive minimum. A valid layout with minimum
width 5, rescaled to width 5, produced leaf widths `{3, 1, -1, 1}` in a direct
probe. This can fail `nvim_open_win()` even when the overall layout could fit.
`equalize()` and initial float opening also lack a complete too-small-screen
policy. `can_rebuild_float()` checks only a single pane's minimum, not the tree.

[Window construction](lua/terminal/window.lua) allocates scratch buffers and
windows before publishing `term_winids`; an exception can strand them.
`close_pane_windows()` can leave its module-wide reentrancy flag set if closing
the last ordinary window raises. The attachment block restores `eventignore`,
but it does not roll back the preceding allocations.

Recommended next commit: reserve recursive minima during distribution, reject
unrenderable layouts before closing the current view, and use protected cleanup
for construction/closure. Test nested layouts at their exact minimum, below
minimum, and with injected API failures. This deserves a dedicated change because
the desired below-minimum behavior must be consistent in drawer and float modes.

### Medium: last-visited tab still uses unstable numeric positions

[Tab history](lua/terminal/keymaps.lua) stores `term_prev_tab_idx`.
Filtering/removal now remaps it, but insertion, `move()`, break-to-tab and
cross-Vim-tab transfer do not all remap it. Example: visit tab A, then B; move B
left across A. The previous index can now equal B's index, making last-tab a
no-op instead of returning to A.

Recommended: assign stable entry IDs and resolve history through IDs, or centralize
every order mutation behind one helper that remaps selected and previous entries.
Do not add more separate positional fixups at call sites.

### Medium: digraph lifecycle, unsupported input and misleading fallback

[digraph.lua](lua/terminal/digraph.lua) creates a fresh scratch buffer for each
indicator and closes only the window. Three cancelled sessions left three extra
buffers in a direct callback probe. Set `bufhidden=wipe` or explicitly release the
indicator buffer.

`vim.fn.digraph_get()` requires a two-byte string in the checked Neovim source;
a multibyte or special second key can raise in the scheduled callback. For an
undefined ASCII pair such as `q!`, it returns `!`, so the empty-string fallback
that re-injects both keys is not used. Also validate the job before delayed sends
and end a session before scheduling completion, so queued keys cannot complete
the same session repeatedly. Real terminal input/protocol coverage is still needed.

### Medium: auxiliary job commands conflict with global terminal cleanup

[job.lua](lua/terminal/job.lua) appears intended to leave failed commands visible,
but the global `TermClose` handler deletes their buffers regardless of exit status.
Its failure callback also focuses `prev_win` without checking validity and calls
`startinsert` there, which can enter insert mode in an ordinary editor buffer.
Concurrent jobs share a single `job_bufnr`; close controls only the latest one.
[fugitive.lua](lua/terminal/fugitive.lua) unconditionally invokes
`FugitiveDidChange()` on success.

Recommended: decide whether these are managed terminal tabs or a separate command
runner, give them explicit ownership, and make exit cleanup follow that contract.
Guard stale windows and absent Fugitive. Test success, failure, concurrent jobs,
and closure of the originating window.

### Medium: deferred UI work can outlive its target

The terminal-exit path now captures ownership, but several callbacks in
[autocmds.lua](lua/terminal/autocmds.lua) and
[float_layout.lua](lua/terminal/float_layout.lua) still consult whichever `vim.t`
is current when they run. Mouse drags store a layout without a tab/entry identity;
scheduled focus callbacks sometimes validate a window before scheduling rather
than immediately before using it. File routing in `BufWinEnter` can restore an old
terminal buffer after the pane has been switched or rebuilt.

Recommended: capture tabpage, entry identity and window/buffer handles; validate
all of them in the deferred callback. Coalesce drag updates rather than queueing
one complete layout/render pass per event. Extend this discipline to TabEnter,
overlay refocusing, and mode restoration.

### Medium: global mode/configuration and zoom options cross Vim-tab boundaries

`float_toggle()` changes global config while only rebuilding the current Vim tab.
Other tabs may retain windows of the previous type. Global `cmdheight`/`ruler`
snapshots in [state.lua](lua/terminal/state.lua) are restored on pane closure,
not every transition away from a zoomed tab. Review transitions among multiple
open drawers/floats/zooms and editor-only tabs, including externally closed tabs.

Recommended: make display mode explicitly per Vim tab, or rebuild all affected
views when a global setting changes. Track global option ownership separately
from window construction.

### Medium: process confirmation is a heuristic, and reset bypasses it

[delete()](lua/terminal/init.lua) synchronously runs `pgrep -P` through the shell.
This blocks the UI briefly, depends on an external Unix command, and detects direct
children rather than the PTY foreground process group. Background jobs can trigger
confirmation; missing `pgrep` or non-shell jobs can bypass it. `TermReset` force
deletes the old buffer without using this confirmation.

Recommended: consolidate job lifecycle/confirmation, document platform support,
and evaluate asynchronous child enumeration or a foreground-process mechanism.
Do not describe this as a reliable “job is still running” check: the interactive
shell itself is usually running throughout the session.

### Medium: setup and key configuration have inconsistent contracts

Repeated `setup()` merges configuration but does not rebuild mappings or
autocommands. Transitioning `keys` from `false` to a table can pass a boolean as
the defaults to `vim.tbl_extend`. Most actions accept key lists, but register
paste, digraphs and go-to-tab do not. `keys=false` leaves mouse mappings active;
normal `<C-w>`/`z` overrides cannot be separately configured. Global fallback
mappings replay native commands, not mappings previously installed by the user.

Recommended: either enforce/document one-time setup with validated immutable
defaults, or support teardown/reconfiguration deliberately. Share one binding
helper for list-valued keys. Tests currently cover count semantics, not every
mapping or interaction with another plugin's mappings.

### Lower priority: border, rendering and API edge cases

- [Float borders](lua/terminal/float_layout.lua) implement a canvas rather than
  native borders. A one-element array such as `{ "*" }` is ignored, whereas
  Neovim repeats it around all sides. Partial borders, shadow and per-side
  highlights also differ. The docs now state the narrower support.
- [send()](lua/terminal/init.lua) checks a nonzero handle but not whether the
  window/channel is still valid. An externally closed pane can cause an error.
- `toggle()` saves `winsaveview()` from the current window even if called from
  the editor, and no restoration path reads `term_view`. This is redundant state
  rather than implemented view restoration.
- [TermOpen](lua/terminal/autocmds.lua) applies options, mappings and ownership
  to all terminal buffers, including terminals created by other plugins. Setup
  also clears Neovim's default `nvim.terminal` TermClose handler. This broad scope
  should be an explicit policy, not an accidental consequence of pattern `*`.
- Register paste sends raw register text, while expression paste always adds
  bracketed-paste markers without checking the child application's mode. Test
  both a shell with bracketed paste and a raw reader before promising native
  paste semantics.

## Feature-by-feature review

“Covered” below means the named headless tests exercised representative paths,
not that every combination is proven correct.

| Feature | Implementation and assessment |
| --- | --- |
| Multiple terminal tabs, new/delete/reorder | Entry-owned state is a good design; smoke/lifecycle tests cover creation, deletion, reorder and exit ownership. Last-visited history still needs stable identity. |
| Nested horizontal/vertical panes | Pure frame tree plus drawer/float rendering; split, remove, flatten and toggle round trips covered. Recursive minimum allocation remains a correctness gap. |
| Directional navigation and cycling | Drawer delegates to Neovim; float uses frame ascent/descent and cursor position. Representative nested navigation and explicit counts covered. Boundary/separator cells and all window options are not exhaustively compared. |
| Resize, equalize, move-to-edge | Representative cascade/equalize/splitmove cases covered. Fixed one-cell minima and scoped height redistribution intentionally differ from full Neovim behavior. Split/move sizing counts are not fully implemented. |
| Rotate and exchange | Order, focus and E443 covered. Buffer IDs move through fixed slots; native Neovim moves windows with their sizes. Docs corrected. |
| Drawer, float, zoom and reset-height | Core transitions and drawer-height preservation covered. Partial float defaults and tabline precedence fixed. Tiny-screen rollback and cross-tab global options remain open. |
| Drawer pinning | Feature-detected `winpinned`, disabled for floats; enabled/disabled cases covered on the installed development build. Older versions omit it. |
| Winbar and activity | Focused-pane title, saved focus and one-shot background watchers covered. Event-driven activity avoids per-output redraw after the first update. Click dispatch needs more real-UI coverage. |
| Float canvas and mouse resizing | Synthetic horizontal separator dragging and native drawer pass-through covered; nested drag growth direction fixed. Mouse callbacks need lifetime protection/coalescing. |
| Mode restoration | Central module validates windows and, for scheduled restore, buffer identity. Smoke tests cannot prove interactive Terminal-mode restoration in every focus path; an attached-UI suite is needed. |
| Move to Vim tab and break pane to tab | Entry state and buffer ownership travel together by inspection. Broad permutations and history after index shifts are not covered by the original suite. |
| Registers and digraphs | Basic implementation reviewed against native digraph lookup. No full interactive input suite. Digraph buffer leak and non-ASCII/special input need fixes. |
| OSC notifications, bell and notification jump | Termination/progress filtering fixed and tested with synthetic events/TTY writes. Jump uses owner search and saved focus. OSC 99 is forwarded but its rich metadata is not fully parsed for `vim.notify`. No host-emulator delivery test. |
| OSC titles and terminal buffer naming | Coalesced title refresh, terminal URI namespace, alternate-buffer preservation and placeholder cleanup covered by smoke tests. Pre-0.13 inactive-rename deferral is source-reviewed, not runtime-tested here. |
| Overlay and statusline | Separate rendering modules and cached statusline buffers are sensible; zoom smoke coverage exists. Colorscheme, arbitrary statusline providers and true mouse focus need UI tests. |
| Convenience commands and job/Fugitive helpers | Commands inspected and documented. Auxiliary jobs and reset have inconsistent cleanup/confirmation behavior; see findings above. |
| Public API and configurable keymaps | Exported functions checked against docs. Count handling fixed; stale handles, repeated setup and inconsistent list support remain. |

## Code quality, structure, DRY and performance

The strongest boundary is the pure [frame engine](lua/terminal/frame.lua).
Keep it independent of `vim`; pass explicit policy if window preferences are
eventually supported. The split among state, mode, rendering and user operations
is broadly useful. A rewrite or a generic class/event framework is not justified.

The main structural weakness is that state access is not encapsulated:
`vim.t.term_order` is read/modified/written throughout multiple modules, and
read-like `get_tabs()` also prunes state. The serialized Vim-variable boundary
copies nested trees on access. A future mutation API should own filtering, history,
ownership, activity synchronization and derived `bufs`, while keeping rendering
outside it. Stable IDs would reduce both correctness fixes and bookkeeping.

There are duplicated command dispatch tables for the custom prefix and normal
`<C-w>`, repeated mode restoration logic, and nearly identical attachment blocks
in open/swap. Consolidate only after adding behavior tests; their failure paths
and fallback behavior are not identical. This audit already centralizes float
defaults and size capture. Cosmetic module splits would not address these risks.

Performance observations from code inspection:

- Title updates are coalesced over 100 ms, activity watches detach after their
  first relevant change, and matching-geometry switches reuse windows. Retain
  these choices.
- `get_tabs()`, `find_buf_tab()`, state setters and renderers repeatedly traverse
  and copy the same order/tree during one operation. Prefer one snapshot per
  operation before adding a cache with invalidation complexity.
- Canvas generation allocates an entire width × height text grid on every
  update. Drag callbacks can queue repeated full rendering work. Coalescing and
  skipping unchanged canvas/config writes are the first useful optimizations.
- Structural operations rebuild every pane and overlay, causing allocations,
  autocommands and PTY resizes. Optimize only with an attached UI benchmark and
  correctness tests; replacing this with buffer swaps changes mode/view semantics.
- Startup dimensions divide width by pane count even for stacked/nested splits.
  A new child may see a different initial PTY size from its eventual rectangle.
  Derive startup dimensions from the prospective layout if this affects TUIs.
- No latency or throughput benchmark was performed. These are complexity and
  allocation observations, not measured performance regressions.

## Neovim source checks

References are relative to this repository and point into the requested local
checkout. Re-check against another Neovim version before treating details as stable.

| Contract | Source | Result |
| --- | --- | --- |
| OSC request framing | [terminal.c](../../neovim/neovim/src/nvim/terminal.c), `emit_termrequest` and OSC callback | Sequence excludes its terminator; current version exposes it separately. v0.11 lacks the separate field, so ST fallback is required. |
| Inactive rename/title behavior | [api/buffer.c](../../neovim/neovim/src/nvim/api/buffer.c), `nvim_buf_set_name` | Current code suppresses title/autochdir effects for inactive rename. Existing compatibility deferral is sensible. |
| Count 1 versus omitted count | [window.c](../../neovim/neovim/src/nvim/window.c), `do_window` | Native code distinguishes explicit count; plugin parsing now does too for implemented operations. |
| Navigation | `window.c`, `win_vert_neighbor` / `win_horz_neighbor` | Same broad ancestor/sibling/descent model. Native frames include separators/window decorations, so universal cell-for-cell parity is not established. |
| Close-space selection | `window.c`, `win_altframe` | Native code considers splitbelow/splitright and fixed dimensions; plugin prefers next sibling independently. |
| Equalization and resizing | `window.c`, `win_equal_rec` / `frame_setheight` | Native code considers preferred/minimum/fixed sizes and ancestor room; plugin implements a simpler scoped model. |
| Rotate/exchange | `window.c`, `win_rotate` / `win_exchange` | Native code moves window/frame objects; plugin moves buffer IDs within slots. |
| Digraph fallback and argument shape | [digraph.c](../../neovim/neovim/src/nvim/digraph.c), `f_digraph_get` / `digraph_get` | Undefined ASCII pair returns the second character; API validates two bytes. |
| Border arrays | [api.txt](../../neovim/neovim/runtime/doc/api.txt), `nvim_open_win` | Neovim supports repeating short arrays and per-side details absent from the canvas. |
| Compatibility helpers | v0.11.0 `runtime/lua/vim/shared.lua` and `_editor.lua` | `vim._with({keepalt=true})` and on_key empty-string suppression exist. `_with` remains a private API dependency. |

## Validation and next work

Run all suites with:

```sh
for test in tests/*.lua; do
  nvim --clean --headless -l "$test" || exit 1
done
```

The original suite passed 194 assertions before and after the implementation
changes. Added suites cover OSC framing, lifecycle, key counts, float configuration,
nested drag direction, and saved geometry. Help tags were regenerated.

The next changes should tackle minimum-size/rollback safety, stable tab history,
and job/digraph lifetimes, in that order. Add a supported-version CI matrix and an
attached-UI suite for real key/mouse/mode behavior. Current tests use fixed waits,
assume `/bin/sh`, and do not prove Neovim 0.11 runtime compatibility or Windows
support. Prefer condition-based waits with bounded timeouts as tests expand.
