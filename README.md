# terminal.nvim

Minimalistic terminal plugin for unobtrusive terminal multiplexing within Neovim.

## Features

- Drawer style and floating window modes
- Easily toggle zoom to maximise screen real estate
- Unobtrusive default keymaps in Terminal and Normal mode
- Multiple terminal tabs per Vim tab
- Sortable terminal tabs
- Preserve and restore terminal buffer modes
- Put any register contents while in Terminal mode

## Installation

### Lazy

```lua
return {
    "jasonwoodland/terminal.nvim",
    config = {
        height = 25,
        float = false,
    },
}
```

## Keymaps

| Normal Mode | Terminal Mode | Map (Insert or Terminal Mode) | Action                                                   |
| ----------- | ------------- | ----------------------------- | -------------------------------------------------------- |
| ✅          | ✅            | `CTRL--`                      | Toggle terminal                                          |
|             | ✅            | `CTRL-;`                      | Go to Normal mode                                        |
| ✅          | ✅            | `CTRL-\_`                     | Toggle zoom                                              |
| ✅          | ✅            | `CTRL-SHIFT-N`                | New terminal tab                                         |
| ✅          | ✅            | `CTRL-SHIFT-D`                | Delete current terminal tab                              |
| ✅          | ✅            | `CTRL-SHIFT-[`                | Previous terminal tab                                    |
| ✅          | ✅            | `CTRL-SHIFT-]`                | Next terminal tab                                        |
| ✅          | ✅            | `CTRL-ALT-SHIFT-]`            | Move current terminal tab left                           |
| ✅          | ✅            | `CTRL-ALT-SHIFT-]`            | Move current terminal tab right                          |
|             | ✅            | `CTRL-SHIFT-R {register}`     | Insert the contents of a register (see `:help i_CTRL-R`) |
