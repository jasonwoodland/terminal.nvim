# terminal.nvim

Use Neovim as your terminal multiplexer.

<img width="1408" height="1000" alt="Screenshot 2026-03-08 at 12 01 18 am" src="https://github.com/user-attachments/assets/f765ba3b-9f74-4e26-b947-539b2b1b1c43" />

## Features

- [x] Multiple terminal tabs per Vim tab
- [x] Split panes within terminal tabs
- [x] Unobtrusive, idiomatic keymaps that work in both Terminal and Normal modes
- [x] Toggle fullscreen terminal
- [x] Clickable winbar with terminal tabs
- [x] Fast tab/window switching, reordering and resizing without leaving Terminal mode
- [x] Drawer-style and floating window modes
- [x] Mouse-draggable pane borders in float mode
- [x] Preserve and restore terminal buffer mode when switching focus
- [x] Insert the contents of registers while in Terminal mode
- [x] OSC notification passthrough and bell
- [x] Activity indicator for background terminal tabs
- [x] Confirm before deleting a terminal with a running process
- [x] Fully configurable keymaps

## Requirements

- Neovim >= 0.10

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jasonwoodland/terminal.nvim",
  opts = {},
}
```

## Configuration

Below is the default configuration:

```lua
require("terminal").setup({
  -- Terminal drawer height. Integer for lines, float for percentage (e.g. 0.5 for 50% height)
  height = 0.5,

  -- Show terminal tabs in winbar
  winbar = true,

  -- Floating window mode disabled by default
  float = false,
  -- float = {
  --   padding = { x = 24, y = 4 },  -- Padding from screen edges (columns, rows)
  --   border = "rounded",           -- Border style (see :help nvim_open_win)
  -- },

  -- Set to true for a fullscreen floating zoom, false to set drawer window height to highest possible
  float_zoom = true,

  -- Show tabline when float zoom is active
  float_zoom_show_tabline = true,

  -- Hide cmdline when float zoom is active
  float_zoom_hide_cmdline = false,

  -- OSC notification passthrough
  osc_notifications = true,

  -- Default key map (set any key to false to disable, or set keys = false to disable all)
  keys = {
    toggle = "<C-S-Space>",
    normal_mode = "<C-S-\\>",
    zoom = "<C-S-z>",
    new = "<C-S-n>",
    wincmd = "<C-S-w>",
    delete = "<C-S-c>",
    prev = "<C-S-[>",
    next = "<C-S-]>",
    last_tab = "<C-S-o>",
    last_pane = "<C-S-p>",
    move_prev = "<C-S-M-[>",
    move_next = "<C-S-M-]>",
    paste_register = "<C-S-r>",
    reset_height = "<C-S-=>",
    tab_next = "<C-PageDown>",
    tab_prev = "<C-PageUp>",
    move_to_tab_prev = "<C-M-PageUp>",
    move_to_tab_next = "<C-M-PageDown>",
    last_notification = "<C-S-a>",
  },
})
```

## Keymaps

### Global keymaps

These work anywhere in Normal and/or Terminal mode:

<table>
  <thead>
    <tr>
      <th align="center">Normal</th>
      <th align="center">Terminal</th>
      <th>Map</th>
      <th>Action</th>
    </tr>
  </thead>
  <tbody>
    <tr><th colspan="4" align="left">Toggle & zoom</th></tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-Space&gt;</kbd></td>
      <td>Toggle terminal</td>
    </tr>
    <tr>
      <td align="center"></td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-\&gt;</kbd></td>
      <td>Go to Normal mode</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-z&gt;</kbd></td>
      <td>Toggle zoom</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-=&gt;</kbd></td>
      <td>Reset height to default</td>
    </tr>
    <tr><th colspan="4" align="left">Tabs</th></tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-n&gt;</kbd></td>
      <td>Open a new terminal tab</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-c&gt;</kbd></td>
      <td>Close the current terminal</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-[&gt;</kbd></td>
      <td>Go to the next tab</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-]&gt;</kbd></td>
      <td>Go to the previous tab</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-1&gt;</kbd> &hellip; <kbd>&lt;C-S-9&gt;</kbd></td>
      <td>Go to tab by index</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-M-[&gt;</kbd></td>
      <td>Move the current tab left</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-M-]&gt;</kbd></td>
      <td>Move the current tab right</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-o&gt;</kbd></td>
      <td>Jump to last-visited tab</td>
    </tr>
    <tr><th colspan="4" align="left">Vim tabs</th></tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-PageUp&gt;</kbd></td>
      <td>Go to the previous Vim tab page</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-PageDown&gt;</kbd></td>
      <td>Go to the next Vim tab page</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-M-PageUp&gt;</kbd></td>
      <td>Move the current tab to previous Vim tab page</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-M-PageDown&gt;</kbd></td>
      <td>Move the current tab to next Vim tab page</td>
    </tr>
    <tr><th colspan="4" align="left">Notifications</th></tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-a&gt;</kbd></td>
      <td>Jump to last notification</td>
    </tr>
    <tr><th colspan="4" align="left">Panes</th></tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-v&gt;</kbd></td>
      <td>Split current window vertically in two</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-h&gt;</kbd></td>
      <td>Move cursor one window left of the current one</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-l&gt;</kbd></td>
      <td>Move cursor one window right of the current one</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-p&gt;</kbd></td>
      <td>Jump to last-visited pane</td>
    </tr>
    <tr><th colspan="4" align="left">Registers</th></tr>
    <tr>
      <td align="center"></td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-r&gt;&nbsp;{register}</kbd></td>
      <td>Insert the contents of a register</td>
    </tr>
    <tr>
      <td align="center"></td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-r&gt;&nbsp;=</kbd></td>
      <td>Enter an expression and the results are inserted</td>
    </tr>
  </tbody>
</table>

### Wincmd keymaps

Press <kbd>&lt;C-S-w&gt;</kbd> followed by a sub-key (works in both Normal and Terminal mode):

<table>
  <thead>
    <tr>
      <th>Sub-key</th>
      <th>Action</th>
    </tr>
  </thead>
  <tbody>
    <tr><th colspan="2" align="left">Navigation</th></tr>
    <tr>
      <td><kbd>w</kbd></td>
      <td>Cycle to next pane</td>
    </tr>
    <tr>
      <td><kbd>h</kbd></td>
      <td>Focus pane left</td>
    </tr>
    <tr>
      <td><kbd>l</kbd></td>
      <td>Focus pane right</td>
    </tr>
    <tr>
      <td><kbd>p</kbd></td>
      <td>Close terminal (toggle off)</td>
    </tr>
    <tr><th colspan="2" align="left">Pane management</th></tr>
    <tr>
      <td><kbd>v</kbd></td>
      <td>Vertical split pane</td>
    </tr>
    <tr>
      <td><kbd>c</kbd></td>
      <td>Delete current terminal</td>
    </tr>
    <tr><th colspan="2" align="left">Resize</th></tr>
    <tr>
      <td><kbd>&gt;</kbd></td>
      <td>Grow pane width (accepts count)</td>
    </tr>
    <tr>
      <td><kbd>&lt;</kbd></td>
      <td>Shrink pane width (accepts count)</td>
    </tr>
    <tr>
      <td><kbd>=</kbd></td>
      <td>Equalize pane widths</td>
    </tr>
    <tr>
      <td><kbd>{count}&lt;CR&gt;</kbd></td>
      <td>Set terminal height to {count}</td>
    </tr>
    <tr><th colspan="2" align="left">Move & rotate</th></tr>
    <tr>
      <td><kbd>H</kbd></td>
      <td>Move pane to far left</td>
    </tr>
    <tr>
      <td><kbd>L</kbd></td>
      <td>Move pane to far right</td>
    </tr>
    <tr>
      <td><kbd>r</kbd></td>
      <td>Rotate panes forward</td>
    </tr>
    <tr>
      <td><kbd>R</kbd></td>
      <td>Rotate panes backward</td>
    </tr>
  </tbody>
</table>

### Normal mode `<C-w>` overrides

When focused in a terminal pane window, `<C-w>` sub-keys are overridden to control panes instead of Vim windows. The same sub-keys from the wincmd table above apply. Outside of terminal pane windows, `<C-w>` behaves normally.

## Commands

Basic convenience commands for manipulating standard terminal buffers

<table>
  <thead>
    <tr>
      <th>Command</th>
      <th>Aliases</th>
      <th>Action</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>:TermSplit</code></td>
      <td><code>:st</code>, <code>:tsplit</code></td>
      <td>Open a terminal in a horizontal split</td>
    </tr>
    <tr>
      <td><code>:TermVsplit</code></td>
      <td><code>:vst</code>, <code>:tvsplit</code></td>
      <td>Open a terminal in a vertical split</td>
    </tr>
    <tr>
      <td><code>:TermTab [args]</code></td>
      <td><code>:tt</code>, <code>:ttab</code></td>
      <td>Open a terminal in a new tab</td>
    </tr>
    <tr>
      <td><code>:TermDelete</code></td>
      <td><code>:td</code>, <code>:tdelete</code></td>
      <td>Delete the current terminal buffer</td>
    </tr>
    <tr>
      <td><code>:TermReset</code></td>
      <td></td>
      <td>Reset the terminal (open new, delete old)</td>
    </tr>
  </tbody>
</table>

## Public API

All functions are available on the module table for use in custom keymaps:

```lua
local terminal = require("terminal")

terminal.toggle()                   -- Toggle terminal window
terminal.toggle({ open = true })    -- Only open
terminal.toggle({ open = false })   -- Only close
terminal.zoom()                     -- Toggle zoom
terminal.reset_height()             -- Reset terminal height to default
terminal.new()                      -- Create new terminal tab
terminal.delete()                   -- Delete current terminal
terminal.vsplit()                   -- Split current tab with a new pane
terminal.next()                     -- Switch to next tab
terminal.prev()                     -- Switch to previous tab
terminal.switch(delta, clamp)       -- Switch by delta (wraps by default, clamp=true to stop at ends)
terminal.go_to(index)               -- Go to tab by index (1-based)
terminal.move(direction)            -- Move current tab (-1 = left, 1 = right)
terminal.move_to_vim_tab(direction) -- Move current tab to adjacent Vim tab (-1 = prev, 1 = next)
terminal.go_to_notification()       -- Jump to terminal with last OSC notification
terminal.send(text)                 -- Send text to the current terminal
```

## Inserting registers

While in Terminal mode, you can press `<C-S-r> "` to insert the contents of the unnamed register. Other useful registers include:

- `#`: the alternate file name (the previous buffer file name)
- `*`: the clipboard contents
- `.`: the last inserted text
- `-`: the last small (less than a line) delete register
- `=`: the expression register: you are prompted to enter an expression (see `:help expression`)

See `:help registers` for more information.
