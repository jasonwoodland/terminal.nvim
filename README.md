# terminal.nvim

Minimal plugin for unobtrusive terminal management in Neovim.

## Features

- Drawer-style and floating window modes
- Split panes within terminal groups
- Clickable winbar with terminal tabs
- Unobtrusive, idiomatic keymaps that work in Terminal and Normal modes
- Multiple terminal groups per Vim tab
- Fast group switching and rearranging
- Move terminal groups between Vim tabs
- Toggle zoom to fullscreen floating terminal
- Mouse-draggable pane borders in float mode
- Preserve and restore terminal buffer mode when switching
- Insert the contents of registers while in Terminal mode
- Fully configurable keymaps

## Configuration

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

  -- Default key map (set any key to false to disable, or set keys = false to disable all)
  keys = {
    toggle = "<C-S-/>",
    normal_mode = "<C-;>",
    zoom = "<C-S-->",
    new = "<C-S-t>",
    wincmd = "<C-S-w>",
    delete = "<C-S-c>",
    prev = "<C-S-[>",
    next = "<C-S-]>",
    move_prev = "<C-S-M-[>",
    move_next = "<C-S-M-]>",
    paste_register = "<C-S-r>",
    reset_height = "<C-S-=>",
    tab_next = "<C-PageDown>",
    tab_prev = "<C-PageUp>",
    move_to_tab_prev = "<C-M-PageUp>",
    move_to_tab_next = "<C-M-PageDown>",
  },
})
```

## Keymaps

### Global keymaps

These work anywhere in Normal and/or Terminal mode:

| Normal | Terminal | Map | Action |
| :----: | :------: | --- | ------ |
| | | **Toggle & zoom** | |
| x | x | <kbd>&lt;C-S-/&gt;</kbd> | Toggle terminal |
| | x | <kbd>&lt;C-;&gt;</kbd> | Go to Normal mode |
| x | x | <kbd>&lt;C-S--&gt;</kbd> | Toggle zoom |
| x | x | <kbd>&lt;C-S-=&gt;</kbd> | Reset height to default |
| | | **Groups** | |
| x | x | <kbd>&lt;C-S-t&gt;</kbd> | New terminal group |
| x | x | <kbd>&lt;C-S-c&gt;</kbd> | Delete current terminal |
| x | x | <kbd>&lt;C-S-[&gt;</kbd> | Previous group |
| x | x | <kbd>&lt;C-S-]&gt;</kbd> | Next group |
| x | x | <kbd>&lt;C-S-1&gt;</kbd> ... <kbd>&lt;C-S-9&gt;</kbd> | Go to group by index |
| x | x | <kbd>&lt;C-S-M-[&gt;</kbd> | Move group left |
| x | x | <kbd>&lt;C-S-M-]&gt;</kbd> | Move group right |
| | | **Vim tabs** | |
| x | x | <kbd>&lt;C-PageUp&gt;</kbd> | Previous Vim tab |
| x | x | <kbd>&lt;C-PageDown&gt;</kbd> | Next Vim tab |
| x | x | <kbd>&lt;C-M-PageUp&gt;</kbd> | Move group to previous Vim tab |
| x | x | <kbd>&lt;C-M-PageDown&gt;</kbd> | Move group to next Vim tab |
| | | **Panes** | |
| | x | <kbd>&lt;C-S-v&gt;</kbd> | Vertical split pane |
| | x | <kbd>&lt;C-S-h&gt;</kbd> | Focus pane left |
| | x | <kbd>&lt;C-S-l&gt;</kbd> | Focus pane right |
| | | **Registers** | |
| | x | <kbd>&lt;C-S-r&gt;&nbsp;{register}</kbd> | Insert contents of a register |
| | x | <kbd>&lt;C-S-r&gt;&nbsp;=</kbd> | Evaluate expression and insert result |

### Wincmd keymaps

Press <kbd>&lt;C-S-w&gt;</kbd> followed by a sub-key (works in both Normal and Terminal mode):

| Sub-key | Action |
| --- | --- |
| **Navigation** | |
| <kbd>w</kbd> | Cycle to next pane |
| <kbd>h</kbd> | Focus pane left |
| <kbd>l</kbd> | Focus pane right |
| <kbd>p</kbd> | Close terminal (toggle off) |
| **Pane management** | |
| <kbd>v</kbd> | Vertical split pane |
| <kbd>c</kbd> | Delete current terminal |
| **Resize** | |
| <kbd>></kbd> | Grow pane width (accepts count) |
| <kbd><</kbd> | Shrink pane width (accepts count) |
| <kbd>=</kbd> | Equalize pane widths |
| <kbd>{count}&lt;CR&gt;</kbd> | Set terminal height to {count} |
| **Move & rotate** | |
| <kbd>H</kbd> | Move pane to far left |
| <kbd>L</kbd> | Move pane to far right |
| <kbd>r</kbd> | Rotate panes forward |
| <kbd>R</kbd> | Rotate panes backward |

### Normal mode `<C-w>` overrides

When focused in a terminal pane window, `<C-w>` sub-keys are overridden to control panes instead of Vim windows. The same sub-keys from the wincmd table above apply. Outside of terminal pane windows, `<C-w>` behaves normally.

## Public API

All functions are available on the module table for use in custom keymaps:

```lua
local terminal = require("terminal")

terminal.toggle()              -- Toggle terminal window
terminal.toggle({ open = true })  -- Only open
terminal.toggle({ open = false }) -- Only close
terminal.zoom()                -- Toggle zoom
terminal.reset_height()        -- Reset terminal height to default
terminal.new()                 -- Create new terminal group
terminal.delete()              -- Delete current terminal
terminal.vsplit()              -- Split current group with a new pane
terminal.next()                -- Switch to next group
terminal.prev()                -- Switch to previous group
terminal.switch(delta, clamp)  -- Switch by delta (wraps by default, clamp=true to stop at ends)
terminal.go_to(index)          -- Go to group by index (1-based)
terminal.move(direction)       -- Move current group (-1 = left, 1 = right)
terminal.move_to_tab(direction) -- Move current group to adjacent Vim tab (-1 = prev, 1 = next)
```

## Inserting registers

While in Terminal mode, you can press `<C-S-r> "` to insert the contents of the unnamed register. Other useful registers include:

- `#`: the alternate file name (the previous buffer file name)
- `*`: the clipboard contents
- `.`: the last inserted text
- `-`: the last small (less than a line) delete register
- `=`: the expression register: you are prompted to enter an expression (see `:help expression`)

See `:help registers` for more information.
