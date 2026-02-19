# terminal.nvim

Minimal terminal plugin for unobtrusive terminal buffer management in Neovim.

## Features

- Toggleable drawer-style and floating window modes
- Toggle zoom to utilise screen real estate
- Unobtrusive, idiomatic keymaps that work in Terminal and Normal modes
- Multiple terminal tabs per Vim tab
- Rearrange terminal tabs
- Preserve and restore terminal buffer mode when switching buffers/windows
- Insert the contents of any register while in Terminal mode
- Fully configurable keymaps
- Floating zoom for near-fullscreen terminal buffers

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

  -- Default key map
  keys = {
    toggle = "<C-->",
    normal_mode = "<C-;>",
    zoom = "<C-S-->",
    new = "<C-S-n>",
    delete = "<C-S-c>",
    prev = "<C-S-[>",
    next = "<C-S-]>",
    move_prev = "<C-S-M-[>",
    move_next = "<C-S-M-]>",
    paste_register = "<C-S-r>",
    tab_next = "<C-PageDown>",
    tab_prev = "<C-PageUp>",
  },
})
```

## Keymaps

| Normal | Terminal | Map                                      | Action                                                   |
| :----: | :------: | ---------------------------------------- | -------------------------------------------------------- |
|   ✓    |    ✓     | <kbd>&lt;C--&gt;</kbd>                   | Toggle terminal                                          |
|        |    ✓     | <kbd>&lt;C-;&gt;</kbd>                   | Go to Normal mode                                        |
|   ✓    |    ✓     | <kbd>&lt;C-S--&gt;</kbd>                 | Toggle zoom                                              |
|   ✓    |    ✓     | <kbd>&lt;C-S-n&gt;</kbd>                 | New terminal tab                                         |
|   ✓    |    ✓     | <kbd>&lt;C-S-c&gt;</kbd>                 | Delete current terminal tab                              |
|   ✓    |    ✓     | <kbd>&lt;C-S-[&gt;</kbd>                 | Previous terminal tab                                    |
|   ✓    |    ✓     | <kbd>&lt;C-S-]&gt;</kbd>                 | Next terminal tab                                        |
|   ✓    |    ✓     | <kbd>&lt;C-M-S-[&gt;</kbd>               | Move current terminal tab left                           |
|   ✓    |    ✓     | <kbd>&lt;C-M-S-]&gt;</kbd>               | Move current terminal tab right                          |
|        |    ✓     | <kbd>&lt;C-S-r&gt;&nbsp;{register}</kbd> | Insert the contents of a register (see `:help i_CTRL-R`) |

## Public API

All functions are available on the module table for use in custom keymaps:

```lua
local terminal = require("terminal")

terminal.toggle()          -- Toggle terminal window
terminal.zoom()            -- Toggle zoom
terminal.new()             -- Create new terminal tab
terminal.delete()          -- Delete current terminal tab
terminal.next()            -- Switch to next terminal tab
terminal.prev()            -- Switch to previous terminal tab
terminal.switch(delta, clamp)  -- Switch by delta (wraps by default, clamp=true to stop at ends)
terminal.go_to(index)      -- Go to terminal tab by index (1-based)
terminal.move(direction)   -- Move current tab (-1 = left, 1 = right)
```

## Inserting registers

While in Terminal mode, you can press `<C-S-r> "` to insert the contents of the unnamed register. Other useful registers include:

- `#`: the alternate file name (the previous buffer file name)
- `*`: the clipboard contents
- `.`: the last inserted text
- `-`: the last small (less than a line) delete register
- `=`: the expression register: you are prompted to enter an expression (see `:help expression`)

See `:help registers` for more information.
