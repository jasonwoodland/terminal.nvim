# terminal.nvim

Manage terminal tabs and split panes inside Neovim. Each Neovim tab page has
its own terminal workspace, which you can open as a bottom drawer or a floating
window.

<img width="1912" height="1242" alt="Screenshot 2026-07-13 at 3 46 15 pm" src="https://github.com/user-attachments/assets/312fa1ca-1be2-48de-ba23-cf7200a8e633" />

## Features

- Open multiple terminal tabs per Neovim tab page and nest horizontal and vertical splits in each.
- Use Vim-style commands to navigate, resize, rotate, exchange, and move panes to the edge of the layout.
- Switch and reorder tabs or resize panes without leaving Terminal mode. Each pane remembers its mode when you switch focus.
- Toggle between a bottom drawer and a floating window, zoom to fill the editor, or drag pane borders in float mode.
- Click terminal tabs in the winbar or scroll over it to switch tabs. Activity indicators mark background tabs with new output.
- [Follow live output and browse scrollback in unfocused panes](#mouse-scrolling-and-output-following) without moving focus.
- Insert registers and digraphs directly in Terminal mode.
- Receive terminal bells and OSC notifications, and jump to the pane that sent the latest notification.
- Confirm before deleting or resetting a terminal with child processes.
- Customize or disable the default keymaps.
- Restore terminal workspaces with `:restart` and native sessions on Neovim 0.13+.

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

  -- Drawer-mode window options
  drawer = {
    winpinned = true,              -- Keep drawer panes open during :only and :fclose
  },

  -- Enable terminal tabs in winbar (shown for 2+ terminal tabs by default)
  winbar = true,

  -- Show winbar even when there is only one terminal tab (requires winbar = true)
  show_winbar_when_single_tab = false,

  -- Floating window mode. Set `enabled = true` (or use the float toggle keymap)
  -- to switch from drawer to float. The other fields define the float layout.
  float = {
    enabled = false,                -- Start in drawer mode; toggle with <C-S-f>
    padding = { x = 24, y = 4 },    -- Padding from screen edges (columns, rows)
    border = false,                 -- false, "single", "double", "rounded", or "solid"
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

  -- Answer OSC 10/11 color queries using the Normal highlight
  osc_colors = true,

  -- Command-line abbreviations, e.g. :st -> :TermSplit
  cabbrev = true,

  -- Keyboard mappings (false disables a key; keys = false disables keyboard maps)
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
    last_tab = "<C-S-Tab>",
    last_pane = "<C-S-p>",
    pane_left = "<C-S-h>",
    pane_down = "<C-S-j>",
    pane_up = "<C-S-k>",
    pane_right = "<C-S-l>",
    vsplit = "<C-S-v>",
    split = "<C-S-s>",
    break_to_tab = "<C-S-t>",
    go_to_tab = "<C-S-%d>",      -- %d is replaced with 1-9
    move_prev = "<C-S-M-[>",
    move_next = "<C-S-M-]>",
    paste_register = "<C-S-r>",
    digraph = "<C-S-i>",
    equalize = "<C-S-=>",
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

Normal-mode shortcuts are global; Terminal-mode shortcuts apply only to managed panes:

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
      <td>Equalize pane heights and widths</td>
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
      <td><kbd>&lt;C-S-Tab&gt;</kbd></td>
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
      <td>Move the current Vim tab page left</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-M-PageDown&gt;</kbd></td>
      <td>Move the current Vim tab page right</td>
    </tr>
    <tr>
      <td align="center">✓</td><td align="center">✓</td>
      <td><kbd>&lt;C-S-M-PageUp&gt;</kbd> / <kbd>&lt;C-S-M-PageDown&gt;</kbd></td>
      <td>Move the current terminal tab to the previous / next Vim tab page</td>
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
      <td><kbd>&lt;C-S-j&gt;</kbd></td>
      <td>Move cursor one window below the current one</td>
    </tr>
    <tr>
      <td align="center">✓</td>
      <td align="center">✓</td>
      <td><kbd>&lt;C-S-k&gt;</kbd></td>
      <td>Move cursor one window above the current one</td>
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
    <tr>
      <td align="center">✓</td><td align="center">✓</td>
      <td><kbd>&lt;C-S-s&gt;</kbd></td>
      <td>Split the current pane horizontally</td>
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
      <td><kbd>&lt;C-S-i&gt;&nbsp;{char1}{char2}</kbd></td>
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
      <td>Jump to the last-visited terminal pane, like &lt;C-S-p&gt; in every display mode</td>
    </tr>
    <tr>
      <td><kbd>t</kbd> / <kbd>b</kbd></td>
      <td>Focus the top-left / bottom-right window (drawer: includes editor windows; float: current tab's panes)</td>
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
      <td><kbd>o</kbd></td>
      <td>Keep the current pane and close its siblings; confirm once with the number of panes running active processes. Declining closes none.</td>
    </tr>
    <tr>
      <td><kbd>T</kbd></td>
      <td>Break current pane out into its own tab after the current tab (requires multiple panes)</td>
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
      <td>Set the focused pane's height to {count}</td>
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

Terminal panes nest in rows and columns like Neovim splits. In drawer mode,
navigation can also move focus into editor windows. In float mode, navigation
stays within the terminal panes. Height commands redistribute space between
panes first. Drawers grow only when neighbouring panes reach their minimum
height; shrinking a pane gives space back to its neighbours. A full-height
pane moves the drawer boundary when no stacked neighbour can take the space.
Side-by-side peers share their row's height. Floats retain their outer bounds.
Use `TermResize` to resize the whole workspace proportionally.
New splits open to the right or below the current pane. Rotating or exchanging
panes preserves their positions' sizes. Closing a pane gives its space to the
next sibling when available. Panes can shrink to one cell.

### Normal mode `<C-w>` overrides

When focused in a terminal pane window, `<C-w>` sub-keys are overridden to control panes instead of Vim windows. The same sub-keys from the wincmd table above apply. Break pane to tab uses uppercase `<C-w>T` or `<C-S-w> T`; the `<C-S-t>` shorthand also works. It moves the current pane into a new terminal tab immediately after the current tab, and does nothing if the tab has only one pane. The `{count}<CR>` pane-height command is only available through `<C-S-w>`. These overrides are buffer-local; mappings outside managed buffers are unchanged.

`z{height}<CR>` also sets the focused pane's height in Normal mode, using the same drawer/float behaviour. All other `z` commands (`zz`, `zt`, folds, plain `z<CR>`) pass through untouched.

### Mouse scrolling and output following

terminal.nvim keeps live output visible in unfocused panes left in Terminal
mode. Leave a pane in Normal mode to keep your place in its scrollback.

- **Browse scrollback without changing focus.** Scroll up over an unfocused pane
  to pause following and read earlier output. Scroll back to the live screen
  to resume. The wheel stops at the live screen.
- **Toggle output following from the mouse menu.** Right-click an unfocused
  pane and select **Follow output**. The check mark
  shows whether following is on. Turning it on jumps to the live screen
  without taking focus. Press Escape to dismiss the menu.
- **Return to Terminal mode.** Right-click the focused pane in Normal mode and
  select **Enter terminal mode** to return to live output.

Clicking or navigating into a pane paused by the wheel keeps its scrollback
position in Normal mode. Scroll back to the live screen to resume Terminal
mode if the pane was in Terminal mode before scrolling.

terminal.nvim also forwards vertical wheel input to mouse-aware applications
such as htop in unfocused panes left in Terminal mode. The pane must be
following output and the application must have enabled mouse reporting.
Otherwise the wheel browses the terminal buffer as described above.
Legacy, UTF-8, urxvt, and SGR cell reporting support forwarding. Pixel reporting
uses scrollback, and using the alternate screen alone leaves forwarding off.

Clicking an unfocused mouse-aware pane left in Terminal mode focuses it and
passes the initial click, drag, and release to the application through Neovim.
A drag stays with its original pane until release, with positions outside the
pane clamped to its nearest cell. Focused panes in Terminal mode use Neovim's
native mouse handling, and panes left in Normal mode support text selection.

## Commands

Commands for managed terminal tabs and panes:

Command-line aliases are enabled by default; set `cabbrev = false` to disable
them. They expand only when the command line contains exactly the alias.

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
      <td><code>:TermNew [command]</code></td>
      <td><code>:tnew</code></td>
      <td>Create a terminal tab, optionally running a shell command</td>
    </tr>
    <tr>
      <td><code>:TermSplit [command]</code></td>
      <td><code>:st</code>, <code>:tsplit</code></td>
      <td>Open a terminal in a horizontal split</td>
    </tr>
    <tr>
      <td><code>:TermVsplit [command]</code></td>
      <td><code>:vst</code>, <code>:tvsplit</code></td>
      <td>Open a terminal in a vertical split</td>
    </tr>
    <tr>
      <td><code>:TermDelete</code></td>
      <td><code>:td</code>, <code>:tdelete</code></td>
      <td>Delete the current terminal buffer</td>
    </tr>
    <tr>
      <td><code>:TermTabClose</code></td>
      <td><code>:ttabclose</code></td>
      <td>Close every pane in the selected terminal tab, confirming if any pane has running programs</td>
    </tr>
    <tr>
      <td><code>:TermReset</code></td>
      <td><code>:treset</code></td>
      <td>Replace the current terminal job, preserving its pane</td>
    </tr>
    <tr>
      <td><code>:TermResize [size]</code></td>
      <td><code>:tresize</code></td>
      <td>Set height, or float width×height; omit size to reset</td>
    </tr>
    <tr>
      <td><code>:TermRename [name]</code></td>
      <td><code>:trename</code></td>
      <td>Rename the current pane; omit name to prompt, use <code>:TermRename!</code> to clear</td>
    </tr>
    <tr>
      <td><code>:TermPicker</code></td>
      <td><code>:tpicker</code></td>
      <td>Navigate to a terminal pane using Telescope (optional)</td>
    </tr>
  </tbody>
</table>

Use `:tabnew | TermNew` to open a managed terminal in a new Vim tab.

`:TermTabClose` closes the selected terminal tab in the current Vim tab, even
from an editor window or while the workspace is hidden. It asks once if any
pane has child processes, runs a program directly, or cannot be inspected.
Cancelling keeps all panes.

`:TermResize 24` sets the workspace height in rows; `:TermResize 50%` uses
half the available editor area. Floats also accept `:TermResize 120x24` or
`:TermResize 80%x50%` (width×height). Use `x` as the separator. Drawers stay
full width. `:TermResize` resets the current mode's configured size.
Resizing retains pane proportions, exits zoom, and leaves hidden terminals
hidden. Sizes belong to the current Vim tab and survive native sessions;
percentage sizes follow changes to the Neovim window size.

`:TermJob {command}` runs a command in a temporary terminal split;
`:TermJobClose` closes the newest remaining job buffer, including a running job.
Successful jobs close automatically; failed output remains visible, with the exit
status in `b:terminal_job_status`. These jobs are separate from managed terminal
tabs. `:FugitiveJob {command}` also calls Fugitive's refresh hook on success and
requires vim-fugitive.

Keyboard configuration does not disable the terminal mouse handlers. The normal
`<C-w>` and `z` overrides are installed whenever `keys` is not `false`.
Each action accepts a string, a list of strings, or `false`; `go_to_tab` strings
must include an integer placeholder such as `%d`.

Delete and reset use `nvim_get_proc_children()` to check for direct children of the
terminal job and ask before closing them, or if inspection fails. This includes
background jobs and does not detect the PTY foreground process group. The check
is synchronous; Neovim may fall back to `pgrep` on some platforms.

Display-mode toggles affect the current Vim tab only; `float.enabled` defines the
initial mode for new Vim tabs. Zoom restores command-line/ruler options when you
leave its tab or close its panes. Operations that cannot fit the recursive pane
minimums are rejected before replacing the current view.

Only terminals created through this plugin's tabs and panes are managed.
Ordinary `:term` buffers and other plugins' terminals are excluded from the
picker, mode tracking, input mappings, title handling, notifications and color
queries, and retain their native exit behavior. Managed terminals are deleted
on exit regardless of status. Auxiliary jobs retain their separate policy above.
Closing a Vim tab moves its managed terminal tabs to the Vim tab you land in,
including hidden panes, preserving their jobs, layouts and names. They are
appended without changing the destination's selection or drawer visibility.
Ordinary terminals are unaffected.

With `osc_colors = true`, OSC 10/11 queries from terminal applications receive
the current `Normal` foreground/background when `termguicolors` is enabled.
This keeps application backgrounds, such as Codex's prompt, consistent with the
colorscheme. This applies only to managed terminals, retaining Neovim's
light/dark fallback for unset colors or cterm rendering.
Window-specific highlights, transparency blending, and inherited host-terminal
colors are not resolved. Set `osc_colors = false` to retain Neovim's handler or
use your own responder. Remove any existing color-query workaround before enabling it.

## Public API

Call `setup()` once before using the plugin. Later calls with options raise an error;
empty calls are harmless. These functions are available for custom keymaps:

```lua
local terminal = require("terminal")

terminal.toggle()                   -- Toggle terminal window
terminal.toggle({ open = true })    -- Only open
terminal.toggle({ open = false })   -- Only close
terminal.zoom()                     -- Toggle zoom
terminal.float_toggle()             -- Toggle between float and drawer mode
terminal.resize()                   -- Reset workspace size to configured defaults
terminal.resize({ height = 24 })    -- Set height (rows or "50%")
terminal.resize({ width = "80%", height = "50%" }) -- Float width and height
terminal.equalize()                 -- Equalize pane heights and widths
terminal.reset(bufnr)               -- Replace a pane's job; omit bufnr for the current pane
terminal.rename("Frontend")        -- Set current pane's winbar/picker name; "" restores its automatic title
terminal.new()                      -- Create new terminal tab
terminal.delete(bufnr)              -- Delete a pane; omit bufnr for the current pane
terminal.close_tab()                -- Close all panes in the selected terminal tab
terminal.only()                     -- Keep the current pane; close its siblings after confirmation
terminal.vsplit()                   -- Split the current pane side by side
terminal.hsplit()                   -- Split the current pane stacked
terminal.break_pane_to_tab()        -- Move the current pane into its own terminal tab
terminal.split(dir)                 -- Split explicitly: "row" or "col"
terminal.next()                     -- Switch to next tab
terminal.prev()                     -- Switch to previous tab
terminal.switch(delta, clamp)       -- Switch by delta (wraps by default, clamp=true to stop at ends)
terminal.go_to(index)               -- Go to tab by index (1-based)
terminal.move(direction)            -- Move current tab (-1 = left, 1 = right)
terminal.move_to_vim_tab(direction) -- Move current tab to adjacent Vim tab (-1 = prev, 1 = next)
terminal.go_to_notification()       -- Jump to terminal with last OSC notification
terminal.list()                     -- List managed panes across all Vim tabs
terminal.focus(bufnr)               -- Navigate to the owning Vim tab, terminal tab and pane
terminal.send(text)                 -- Raw send to the last focused pane in this Vim tab, even hidden
terminal.send(text, bufnr)          -- Raw send to an explicit managed pane in any Vim tab
```

`send()` preserves focus and mode and leaves hidden panes hidden. It sends the
string exactly as supplied, without adding a newline or paste markers, and
returns `true` or `false, reason`. Use `terminal.send(vim.fn.getreg("a"))` to
send a register's contents as raw input.

`delete(bufnr)` and `reset(bufnr)` can target hidden panes or panes in other Vim
tabs without opening them or changing the caller's focus. Both default to the
current pane and retain the running-process confirmation. `delete()` returns
`true`; `reset()` returns the replacement buffer number. Both return
`false, reason` for cancellation, an invalid target, or failure.

`go_to(index)`, `switch(delta, clamp)`, `next()` and `prev()` select terminal tabs
in the current Vim tab. A hidden workspace stays hidden; reopening shows the
selected tab. They return `true` on success (including an unchanged selection)
or `false, reason` for invalid arguments, missing tabs, or a failed switch.
`index` is a positive integer; `delta` is an integer and wraps by default.
Pass `true` for `clamp` to stop at either end. The last-tab mapping also works
while hidden, preserving selection history.

`move(direction)` reorders the selected terminal tab, including while hidden.
`move_to_vim_tab(direction)` transfers the focused pane's entire terminal tab
to the adjacent Vim tab and follows it. Both require `-1` or `1` and wrap.
`break_pane_to_tab()` moves the focused pane into a new terminal tab immediately
after its source. All three return `true` or `false, reason`; reordering a lone
terminal tab succeeds without changes, while breaking a lone pane fails.
Transfer and break require focus inside a managed terminal pane.

`toggle()`, `zoom()`, `float_toggle()` and `equalize()` return `true` or
`false, reason`. `toggle()` accepts only an optional `{ open = true/false }`
table; invalid options leave the workspace unchanged. Display failures restore
the previous mode settings. `go_to_notification()` returns the result of
focusing the notifying pane, or `false, reason`, and keeps its warning when
no notification is available.

`new(opts)`, `vsplit(opts)`, `hsplit(opts)` and `split(dir, opts)` accept optional
launch settings and return the new buffer number:

```lua
terminal.new({
  cmd = { "npm", "run", "dev" },
  cwd = "~/project",
  env = { PORT = "3001" },
  name = "Frontend",
})
```

`cmd` accepts an argument list (run directly) or a string (run through the shell).
Defaults are `$SHELL` or `&shell`, inherited environment, and an automatic title.
New splits and terminal tabs inherit the invoking terminal pane's current
directory, detected from the shell process on Linux and macOS (using `lsof`
on macOS), with OSC 7 shell reports as a fallback. Without a usable directory,
they use that pane's original launch directory, then Neovim's current directory.
When invoked from an editor window (including a new Neovim tab), they use that
window's effective Neovim directory. An explicit `cwd` always takes precedence.
Remote OSC 7 hosts are ignored. `env` adds or overrides variables; values must
be strings. Commands, environment overrides and names are not inherited.
`reset()` restarts the original command, directory and environment overrides,
retaining the current custom name. Invalid options and process-start failures
preserve existing panes.

`list()` returns one record per managed pane, in Vim-tab/terminal-tab/pane order:
`{ bufnr, tabpage, tabnr, tab_id, tab_index, pane_index, title }`. `bufnr` and
`tabpage` are Neovim handles; `tabnr`, `tab_index` and `pane_index` are 1-based
display positions. `tab_id` identifies the terminal tab across reordering and
Vim-tab moves. Handles and IDs last only for the current Neovim session.

`focus(bufnr)` resolves the pane's current location, opens its workspace if
hidden, and restores its saved terminal mode. It returns `true` on success or
`false, reason` for a stale/unmanaged buffer or an unavailable layout. It does
not open the terminal buffer in the current editor window.

`rename(name, bufnr)` names the current managed pane, or an explicit buffer.
Custom names override OSC titles in the winbar and picker, survive resets and
pane moves, and leave the terminal buffer URI unchanged. An empty name restores
the automatic title. Returns `true`, or `false, reason` for invalid names or
unmanaged buffers.

## Restart and sessions

On Neovim 0.13+ (with `SessionWritePre`), `:restart` automatically restores terminal
workspaces in their original Vim tabs alongside Neovim's editor session. This
also works with `:mksession` and respects `sessionoptions`' `terminal`/`tabpages`
settings. `:restart!` discards the session as usual.

Terminal tabs, pane sizes, focus/modes, names, launch settings and view modes are
preserved. Each pane's current working directory is captured when saving, so
`cd` changes survive restart, including in hidden panes. Directory detection
uses the same fallbacks as new panes. Jobs start fresh; scrollback and commands
typed into a shell are not saved.

## Telescope integration

With [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed:

```lua
require("telescope").load_extension("terminal")
vim.keymap.set("n", "<space>t", function()
  require("telescope").extensions.terminal.terminals()
end, { desc = "Terminals" })
```

Also available as `:TermPicker` or `:Telescope terminal terminals`. Select a pane
to navigate to its Vim tab and terminal workspace, including hidden panes.
Live previews match the terminal's scroll position and display plain text.
Pass Telescope options to `terminals(opts)` to customize the picker.

## Inserting registers

While in Terminal mode, you can press `<C-S-r> "` to insert the contents of the unnamed register. Other useful registers include:

- `#`: the alternate file name (the previous buffer file name)
- `*`: the clipboard contents
- `.`: the last inserted text
- `-`: the last small (less than a line) delete register
- `=`: the expression register: you are prompted to enter an expression (see `:help expression`)

Register and expression paste use Neovim's native paste handling. Bracketed-paste
markers are sent only when the terminal application requests them; native paste
filters apply where supported. Results are discarded if the prompt or expression
switches away from the originating terminal. `terminal.send()` remains a raw
channel send.

See `:help registers` for more information.

## Appendix

### Starting as a fullscreen terminal multiplexer

If your workflow starts from the shell, you can launch Neovim directly into a fullscreen terminal.nvim session:

```sh
nvim +"lua require('terminal').toggle()" +"lua require('terminal').zoom()"
```

This assumes your configuration already calls `terminal.setup()`. It opens the terminal and zooms it to fill the editor area.

## Contributing

All issues and PRs are welcome. Run the regression suites from the repo root
with Neovim and Python 3 installed:

```sh
python3 scripts/test.py
# Test a specific binary or suite:
python3 scripts/test.py --nvim /path/to/nvim tests/input.lua tests/ui.lua
```

The runner checks exit codes, timeouts, and asynchronous Lua errors. Input/mouse
suites attach an RPC UI to an embedded Neovim and use real input events and PTYs;
no GUI, Python packages, or external Neovim test framework is needed. Other suites
run headlessly. CI covers Linux/macOS on Neovim 0.11.0, 0.12.0, stable, and nightly.

See [the implementation audit](AUDIT.md) for verified behavior and remaining
limits, and [the benchmark](benchmarks/README.md) for reproducible measurements.
