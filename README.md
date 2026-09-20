# terminal.nvim

Use Neovim as your terminal multiplexer.

<img width="1912" height="1242" alt="Screenshot 2026-07-13 at 3 46 15 pm" src="https://github.com/user-attachments/assets/312fa1ca-1be2-48de-ba23-cf7200a8e633" />

## Features

- Multiple terminal tabs per Vim tab
- Split panes within terminal tabs — vertical and horizontal, nesting like vim windows
- The full vim `CTRL-W` command set over panes (splits, directional navigation, resize cascades, rotate/exchange, move-to-edge), matching vim's exact semantics in both drawer and float mode
- Unobtrusive, idiomatic keymaps that work in both Terminal and Normal modes
- Toggle fullscreen terminal
- Clickable winbar with terminal tabs
- Fast tab/window switching, reordering and resizing without leaving Terminal mode
- Drawer-style and floating window modes
- Mouse-draggable pane borders in float mode
- Preserve and restore terminal buffer mode when switching focus
- Insert the contents of registers while in Terminal mode
- OSC notification passthrough and bell
- Activity indicator for background terminal tabs
- Confirm before deleting a terminal with a running process
- Fully configurable keymaps

## Installation

Requires Neovim 0.11 or newer.

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

  -- Enable terminal tabs in winbar (shown for 2+ terminal tabs by default)
  winbar = true,

  -- Show winbar even when there is only one terminal tab (requires winbar = true)
  show_winbar_when_single_tab = false,

  -- Floating window mode. Set `enabled = true` (or use the float toggle keymap)
  -- to switch from drawer to float. The other fields define the float layout.
  float = {
    enabled = false,                -- Start in drawer mode; toggle with <C-S-f>
    padding = { x = 24, y = 4 },    -- Padding from screen edges (columns, rows)
    border = false,                 -- Border style (see :help nvim_open_win), or false for none
    winblend = 0,                   -- Pseudo-transparency for the float (0-100)
    overlay = {                     -- Dimming backdrop behind the float
      enabled = true,
      winblend = 75,
      hl = "TerminalOverlay",
    },
  },

  -- Set to true for a fullscreen floating zoom, false to set drawer window height to highest possible
  float_zoom = true,

  -- Show tabline when float zoom is active
  float_zoom_show_tabline = true,

  -- Hide cmdline when float zoom is active
  float_zoom_hide_cmdline = false,

  -- Name terminal buffers term://{terminal job PID}//{OSC title}
  -- (on Neovim <0.13, inactive renames wait until the terminal is focused)
  -- Neovim's own title/titlestring handling then follows the active buffer.
  set_buffer_name = true,

  -- OSC notification passthrough
  osc_notifications = true,

  -- Default key map (set any key to false to disable, or set keys = false to disable all)
  keys = {
    toggle = "<C-S-Space>",
    normal_mode = "<C-S-\\>",
    zoom = "<C-S-z>",
    float_toggle = "<C-S-f>",
    new = "<C-S-n>",
    wincmd = "<C-S-w>",
    delete = "<C-S-c>",
    prev = "<C-S-[>",
    next = "<C-S-]>",
    last_tab = "<C-S-o>",
    last_pane = "<C-S-p>",
    pane_left = "<C-S-h>",
    pane_right = "<C-S-l>",
    vsplit = "<C-S-v>",
    split = "<C-S-s>",
    break_to_tab = "<C-S-t>",
    go_to_tab = "<C-S-%d>",      -- %d is replaced with 1-9
    move_prev = "<C-S-M-[>",
    move_next = "<C-S-M-]>",
    paste_register = "<C-S-r>",
    digraph = "<C-S-k>",
    reset_height = "<C-S-=>",
    vim_tab_next = "<C-PageDown>",
    vim_tab_prev = "<C-PageUp>",
    vim_tab_move_prev = "<C-M-PageUp>",
    vim_tab_move_next = "<C-M-PageDown>",
    move_to_vim_tab_prev = "<C-S-M-PageUp>",
    move_to_vim_tab_next = "<C-S-M-PageDown>",
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
      <td><kbd>&lt;C-S-f&gt;</kbd></td>
      <td>Toggle float / drawer</td>
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
      <td>Go to the previous tab</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-]&gt;</kbd></td>
      <td>Go to the next tab</td>
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
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-t&gt;</kbd></td>
      <td>Break the current pane out into its own tab</td>
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
    <tr><th colspan="4" align="left">Digraphs</th></tr>
    <tr>
      <td align="center"></td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-k&gt;&nbsp;{char1}{char2}</kbd></td>
      <td>Enter a digraph and send it to the terminal (like <code>i_CTRL-K</code>)</td>
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
      <td><kbd>w</kbd> / <kbd>W</kbd></td>
      <td>Cycle to next / previous pane (count = go to pane <em>N</em>)</td>
    </tr>
    <tr>
      <td><kbd>h</kbd> <kbd>j</kbd> <kbd>k</kbd> <kbd>l</kbd></td>
      <td>Focus pane left / below / above / right (vim's directional rules)</td>
    </tr>
    <tr>
      <td><kbd>p</kbd></td>
      <td>Jump to the previous (last-visited) pane</td>
    </tr>
    <tr><th colspan="2" align="left">Pane management</th></tr>
    <tr>
      <td><kbd>v</kbd></td>
      <td>Split pane vertically (side by side)</td>
    </tr>
    <tr>
      <td><kbd>s</kbd></td>
      <td>Split pane horizontally (stacked)</td>
    </tr>
    <tr>
      <td><kbd>c</kbd></td>
      <td>Delete current terminal (the neighboring pane absorbs the space)</td>
    </tr>
    <tr>
      <td><kbd>t</kbd></td>
      <td>Break current pane out into its own tab</td>
    </tr>
    <tr><th colspan="2" align="left">Resize</th></tr>
    <tr>
      <td><kbd>&gt;</kbd> / <kbd>&lt;</kbd></td>
      <td>Grow / shrink pane width (accepts count)</td>
    </tr>
    <tr>
      <td><kbd>+</kbd> / <kbd>-</kbd></td>
      <td>Grow / shrink pane height (accepts count)</td>
    </tr>
    <tr>
      <td><kbd>_</kbd> / <kbd>|</kbd></td>
      <td>Maximize pane height / width within the terminal (count = set size)</td>
    </tr>
    <tr>
      <td><kbd>=</kbd></td>
      <td>Equalize panes (vim's proportional distribution)</td>
    </tr>
    <tr>
      <td><kbd>{count}&lt;CR&gt;</kbd></td>
      <td>Set terminal height to {count}</td>
    </tr>
    <tr><th colspan="2" align="left">Move & rotate</th></tr>
    <tr>
      <td><kbd>H</kbd> / <kbd>L</kbd></td>
      <td>Move pane to the far left / right as a full-height pane</td>
    </tr>
    <tr>
      <td><kbd>K</kbd> / <kbd>J</kbd></td>
      <td>Move pane to the top / bottom as a full-width pane</td>
    </tr>
    <tr>
      <td><kbd>r</kbd> / <kbd>R</kbd></td>
      <td>Rotate the panes in the current row/column forward / backward</td>
    </tr>
    <tr>
      <td><kbd>x</kbd></td>
      <td>Exchange the current pane with the next one (count = with pane <em>N</em>)</td>
    </tr>
  </tbody>
</table>

Splits nest like vim windows: panes form rows and columns, and all of the
commands above follow vim's `CTRL-W` semantics (researched from the Neovim
source) — including the directional-navigation descent rules, the resize
cascade order, proportional `=` distribution, and `E443` when rotating next
to a split pane.

### Normal mode `<C-w>` overrides

When focused in a terminal pane window, `<C-w>` sub-keys are overridden to control panes instead of Vim windows. The same sub-keys from the wincmd table above apply, except `t` (break pane to tab), which is only available via `<C-S-w> t` or the `<C-S-t>` shorthand. Outside of terminal pane windows, `<C-w>` behaves normally.

`z{height}<CR>` also works in Normal mode inside a pane, like vim: it sets the pane's height (a full-height or single pane resizes the drawer itself; a stacked pane resizes within the drawer). All other `z` commands (`zz`, `zt`, folds, plain `z<CR>`) pass through untouched.

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
terminal.float_toggle()             -- Toggle between float and drawer mode
terminal.reset_height()             -- Reset terminal height to default
terminal.new()                      -- Create new terminal tab
terminal.delete()                   -- Delete current terminal
terminal.vsplit()                   -- Split the current pane side by side
terminal.hsplit()                   -- Split the current pane stacked
terminal.split(dir)                 -- Split explicitly: "row" or "col"
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

## Appendix

### Starting as a fullscreen terminal multiplexer

If your workflow starts from the shell, you can launch Neovim directly into a fullscreen terminal.nvim session:

```sh
nvim +"lua require('terminal').toggle()" +"lua require('terminal').zoom()"
```

This opens terminal.nvim immediately and then zooms it to fill the editor area.

## Contributing

All issues and PRs are welcome.
