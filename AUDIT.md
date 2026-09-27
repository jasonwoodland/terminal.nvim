# Implementation audit — 2026-09-27

Reviewed all Lua modules (21 initially, plus the new paste module), README, help,
and regression suites.
The starting revision was `5518e1c`. Neovim verification used the local checkout
at `../../neovim/neovim`, revision `521edde`, and the matching installed
`v0.13.0-dev-1738+g521edde` executable. Selected compatibility contracts were
also checked in the local `v0.11.0` source tag. The latest pass additionally ran
all 17 suites on downloaded macOS arm64 releases 0.11.0 and 0.12.0. This does not
certify every supported patch release, operating system, or terminal emulator.

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

## Follow-up cleanup commits

The follow-up pass addressed the high- and medium-priority implementation bugs.

| Commit | Change | Regression |
| --- | --- | --- |
| `1900b6b` | Reserve recursive layout minima, reject undersized operations before teardown, clean partial window/startup failures and release close guards | `tests/safety.lua` |
| `739b48f` | Stable entry IDs and centralized order writes preserve selection/history across insertion, reorder, removal and transfer | `tests/history.lua` |
| `aac381f` | Bound digraph sessions, wipe indicators, handle non-ASCII/special input, reject stale completion | `tests/digraph.lua` |
| `12cc57f` | Separate auxiliary job ownership; retain failed output, track concurrent jobs, guard Fugitive dependency and stale callbacks | `tests/jobs.lua` |
| `140dbdf` | Scope deferred UI work to view generation/tab/entry/window/buffer and coalesce mouse drags | `tests/deferred.lua` |
| `582c69f` | Keep display mode per Vim tab and restore zoom options across tab/window lifecycle transitions | `tests/tab_modes.lua` |
| `5bcd4e2` | Reject repeated configuration before mutation, use immutable defaults, validate/support key lists, tolerate stale sends, remove unused view state | `tests/config.lua` |
| `3501021` | Share child-process confirmation through Neovim's API; reset jobs in place and retain the old job on startup failure | `tests/reset.lua` |
| `5c2fa59` | Release replacement buffers when the temporary startup window cannot be created | `tests/reset.lua` |

The minimum-size test includes a nested layout which previously produced a
negative leaf width even at its valid recursive minimum. Failure-injection tests
cover pane opening/attachment, terminal startup and close-guard recovery. Startup
cleanup and layout preflight are covered; arbitrary third-party autocommand
failures do not have a general transactional rollback guarantee.

History is now resolved by entry identity rather than numeric position. Digraph
completion detaches its key listener immediately and validates the captured job
before sending. Auxiliary jobs no longer enter terminal-tab ownership or steal
focus after asynchronous failure. Deferred view tokens invalidate old work even
when a user switches away and back to the same entry before the callback runs.

The command-line height fix accounts for Neovim's own per-tab saved height; a
single module-level snapshot was insufficient when returning to a zoomed tab.
Setup now has an explicit one-time contract: empty subsequent calls are harmless,
but options on subsequent calls raise before altering configuration or mappings.

## Input, compatibility and measured performance follow-up

| Commit | Change | Validation |
| --- | --- | --- |
| `83ff68a` | Share native paste handling for registers/expressions; preserve originating buffer/job across prompts | `tests/input.lua`: attached UI, raw/bracketed PTY byte capture, digraphs, cancellation, stale expressions and shell execution |
| `c8db03f` | Watch native `b:term_title` changes instead of relying on OSC TermRequest delivery | Original title/coalescing suite on Neovim 0.11.0, 0.12.0 and local 0.13 development build |
| `0a6baee` | Keep Terminal mode during custom float dragging | `tests/ui.lua`: real input events, mode restoration, mouse resize and winbar click |
| `7826021` | Add Linux/macOS version matrix and a runner that detects timeouts/asynchronous Lua errors | Runner executed locally on all three binaries; workflow YAML parsed; remote CI awaits push |
| `44d1246` | Cache canvas artwork by drawing inputs and skip unchanged configuration writes | `tests/render.lua` invalidation cases; [benchmark results](benchmarks/README.md) |

Runtime testing reproduced two compatibility/input defects that source-only and
headless checks had missed. Neovim 0.11 updates `b:term_title` without issuing
TermRequest for its handled title OSCs. A dictionary watcher now follows that
native variable on all supported versions, retaining 100 ms coalescing and
pre-0.13 inactive-rename deferral. A custom float drag called `stopinsert` without
restoring the user's mode; custom dragging no longer changes mode unnecessarily.

The attached-UI input test also reproduced forced bracketed-paste markers reaching
a raw reader. Both paste actions now use `nvim_paste()`; actual captured bytes
confirm that bracketed markers follow the child's mode, and multiline text still
works in a shell. Public `send()` intentionally remains a raw channel send.

## Remaining limitations and recommendations

- **Coverage boundaries:** the attached RPC UI exercises real Neovim input and
  mode transitions, but not a host terminal emulator's keyboard/mouse protocol
  encoding or rendering. Broader statusline-provider integration and Windows
  coverage remain open. The new remote CI matrix has not run in this workspace.
- **Process confirmation:** `nvim_get_proc_children()` is synchronous and may
  itself fall back to `pgrep`. It detects direct children, including background
  jobs, rather than the PTY foreground process group. Inspection failure now
  prompts instead of silently permitting deletion. A reliable foreground-job
  policy needs a separate platform-aware design.
- **Borders:** the float canvas supports common rectangular borders; shortened
  arrays, partial borders, shadow and per-side highlights do not have native
  `nvim_open_win()` semantics. Docs explicitly narrow support.
- **Ownership policy:** ordinary terminal buffers from other plugins are adopted,
  and setup replaces Neovim's default terminal-exit handler. Their buffers are
  deleted on exit regardless of status. This is now explicit documentation;
  auxiliary job buffers are excluded. An opt-in ownership filter could improve
  coexistence but would change existing behavior.
- **Mapping policy:** `keys=false` disables keyboard mappings while mouse handlers
  remain. Normal `<C-w>`/`z` overrides have no independent configuration and replay
  native commands outside panes, not previously installed user mappings. The
  contract is documented; adding knobs is optional feature work.

## Feature-by-feature review

“Covered” below means the named headless tests exercised representative paths,
not that every combination is proven correct.

| Feature | Implementation and assessment |
| --- | --- |
| Multiple terminal tabs, new/delete/reorder | Entry-owned state is a good design; smoke/lifecycle tests cover creation, deletion, reorder and exit ownership. Stable-ID history now covers insertion, reordering, removal and transfer. |
| Nested horizontal/vertical panes | Pure frame tree plus drawer/float rendering; split, remove, flatten and toggle round trips covered. Recursive minima and undersized-operation preflight are now covered by safety tests. |
| Directional navigation and cycling | Drawer delegates to Neovim; float uses frame ascent/descent and cursor position. Representative nested navigation and explicit counts covered. Boundary/separator cells and all window options are not exhaustively compared. |
| Resize, equalize, move-to-edge | Representative cascade/equalize/splitmove cases covered. Fixed one-cell minima and scoped height redistribution intentionally differ from full Neovim behavior. Split/move sizing counts are not fully implemented. |
| Rotate and exchange | Order, focus and E443 covered. Buffer IDs move through fixed slots; native Neovim moves windows with their sizes. Docs corrected. |
| Drawer, float, zoom and reset-height | Core transitions and drawer-height preservation covered. Partial float defaults and tabline precedence fixed. Undersized-operation rejection and cross-tab mode/zoom option lifecycles now have dedicated coverage. |
| Drawer pinning | Feature-detected `winpinned`, disabled for floats; enabled/disabled cases covered on the installed development build. Older versions omit it. |
| Winbar and activity | Focused-pane title, saved focus and one-shot background watchers covered. Event-driven activity avoids per-output redraw after the first update. Attached-UI tests now cover winbar click dispatch and restoration of the selected tab's mode. |
| Float canvas and mouse resizing | Synthetic horizontal separator dragging and native drawer pass-through covered; nested drag growth direction fixed. View lifetime checks and burst coalescing have synthetic callback coverage; attached-UI mouse input verifies resizing and Terminal-mode preservation. |
| Mode restoration | Central module validates windows and, for scheduled restore, buffer identity. Attached-UI tests cover hide/reopen, tab switching, float transitions, splits, dragging and winbar clicks in Terminal/Normal modes. All combinations are not exhaustive. |
| Move to Vim tab and break pane to tab | Entry state and buffer ownership travel together by inspection. History tests cover break-to-tab and cross-Vim-tab transfer, including shifted indices. |
| Registers and digraphs | Native paste and digraph input now have attached-UI/PTY coverage. Callback tests additionally cover non-ASCII/special input, resource cleanup and stale completion. |
| OSC notifications, bell and notification jump | Termination/progress filtering fixed and tested with synthetic events/TTY writes. Jump uses owner search and saved focus. OSC 99 is forwarded but its rich metadata is not fully parsed for `vim.notify`. No host-emulator delivery test. |
| OSC titles and terminal buffer naming | Coalesced title refresh, terminal URI namespace, alternate-buffer preservation and placeholder cleanup covered by smoke tests. Native title watching, coalescing and pre-0.13 inactive-rename deferral are now runtime-tested on 0.11.0 and 0.12.0. |
| Overlay and statusline | Separate rendering modules and cached statusline buffers are sensible; zoom smoke coverage exists. Arbitrary statusline providers and colorscheme changes need more integration coverage; attached-UI mouse input is now exercised. |
| Convenience commands and job/Fugitive helpers | Commands inspected and documented. Jobs now have independent ownership and retained failures; reset preserves its pane and shares delete confirmation. |
| Public API and configurable keymaps | Exported functions checked against docs. Count handling, stale sends, atomic one-time setup and list-valued keys are covered. |

## Code quality, structure, DRY and performance

The strongest boundary is the pure [frame engine](lua/terminal/frame.lua).
Keep it independent of `vim`; pass explicit policy if window preferences are
eventually supported. The split among state, mode, rendering and user operations
is broadly useful. A rewrite or a generic class/event framework is not justified.

Order writes now pass through `state.set_term_order()`, and stable entry IDs own
selection/history independently of positions. Reads and mutations still span
multiple modules, and read-like `get_tabs()` also prunes state. The serialized
Vim-variable boundary copies nested trees on access. Further consolidation should
own filtering, activity synchronization and derived `bufs` while keeping rendering
outside state. Avoid a cache until measurements justify its invalidation burden.

There are duplicated command dispatch tables for the custom prefix and normal
`<C-w>`, repeated mode restoration logic, and nearly identical attachment blocks
in open/swap. Consolidate only after adding behavior tests; their failure paths
and fallback behavior are not identical. This audit already centralizes float
defaults and size capture. Cosmetic module splits would not address these risks.

Performance observations and measurements:

- Title updates are coalesced over 100 ms, activity watches detach after their
  first relevant change, and matching-geometry switches reuse windows. Retain
  these choices.
- `get_tabs()`, `find_buf_tab()`, state setters and renderers repeatedly traverse
  and copy the same order/tree during one operation. Prefer one snapshot per
  operation before adding a cache with invalidation complexity.
- Canvas generation allocates an entire width × height text grid on every
  update. Drag events now share one pending render, verified with a burst of
  synthetic events. The new artwork cache keys separator geometry, border,
  title and fillchars, with changedtick invalidation for external edits. It skips
  unchanged buffer/configuration writes without caching terminal-tab state.
- Structural operations rebuild every pane and overlay, causing allocations,
  autocommands and PTY resizes. Optimize only with an attached UI benchmark and
  correctness tests; replacing this with buffer swaps changes mode/view semantics.
- Startup dimensions divide width by pane count even for stacked/nested splits.
  A new child may see a different initial PTY size from its eventual rectangle.
  Derive startup dimensions from the prospective layout if this affects TUIs.
- The [attached-UI microbenchmark](benchmarks/README.md) measured 160 × 50,
  four-pane views on macOS arm64. Across three alternating baseline/candidate
  runs, the median of per-run medians for unchanged canvas refreshes fell from
  0.545 ms to 0.264 ms. Each run eliminated all 110 redundant buffer writes.
  Tab-switch timing was essentially unchanged. These are synchronous operation
  timings including redraw generation, not host-emulator latency or throughput.

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
| Child enumeration | [api/vim.c](../../neovim/neovim/src/nvim/api/vim.c), `nvim_get_proc_children`; [os/proc.c](../../neovim/neovim/src/nvim/os/proc.c); [editor.lua](../../neovim/neovim/runtime/lua/vim/_core/editor.lua), `_os_proc_children` | Native enumeration where available, synchronous pgrep fallback elsewhere; not a foreground-process API. |
| Command-line height across tabs | `window.c`, `leave_tabpage` / `enter_tabpage` / `use_tabpage` and `tp_ch_used` | Neovim stores per-tab height; plugin retains each zoomed tab's original height until unzoom. |
| Native paste | `api/vim.c`, `nvim_paste`; `terminal.c`, `terminal_paste`; Lua `vim.paste` | Routes terminal input through Neovim/libvterm paste handling. Captured bytes verify conditional bracketed markers on all three tested versions. |
| Title notifications on 0.11 | v0.11.0 `terminal.c`, `term_settermprop` / `buf_set_term_title`; `api/private/helpers.c`, `dict_set_var` | Handled titles do not reach the OSC fallback, but native title-variable writes notify dictionary watchers. |
| Compatibility helpers | v0.11.0 `runtime/lua/vim/shared.lua` and `_editor.lua` | `vim._with({keepalt=true})` and on_key empty-string suppression exist. `_with` remains a private API dependency. |

## Validation and next work

Run all suites with Neovim and Python 3 installed:

```sh
python3 scripts/test.py
python3 scripts/test.py --nvim /path/to/another/nvim
```

All 17 scripts passed on macOS arm64 with Neovim 0.11.0, 0.12.0 and local
`v0.13.0-dev-1738+g521edde`. The original suite passes 191 assertions on the older
releases and 194 on the development build; the additional assertions depend on
`winpinned` support. Expected E36/E443 warnings exercise rejected operations;
missing-Fugitive handling is also intentional. The runner detects unexpected Lua
tracebacks and scheduled-callback errors, including errors with a zero exit code.
Help tags were regenerated and `git diff --check` passed.

The committed CI workflow runs Linux/macOS with 0.11.0, 0.12.0, stable and nightly.
It was syntax-checked locally but has not run remotely. New attached-UI tests use
condition-based waits and require only standard Python for the PTY byte reader.
Older headless tests still use some fixed waits. Tests assume `/bin/sh` and do not
establish Windows or host-emulator protocol compatibility.
