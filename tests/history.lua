-- Usage: nvim --clean --headless -l tests/history.lua
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(arg[0], ":p:h:h"))
vim.env.SHELL = "/bin/sh"
local terminal = require("terminal")
local state = require("terminal.state")
terminal.setup({ keys = { last_tab = "<F8>" }, set_buffer_name = false })
local function settle() vim.wait(150, function() return false end) end
local function current_id() return state.get_current_tab().id end
local function previous_id()
	local idx = state.previous_tab_index()
	return idx and state.get_tabs()[idx].id
end
local function last()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F8>", true, false, true), "xt", false)
	settle()
end
terminal.toggle()
settle()
local a = current_id()
terminal.new()
settle()
local b = current_id()
assert(a ~= b and previous_id() == a, "new tab remembers its source")
terminal.move(-1)
assert(current_id() == b and previous_id() == a, "reordering preserves selected and previous identities")
last()
assert(current_id() == a, "last-tab follows the moved entry")
last()
assert(current_id() == b, "last-tab toggles back")

-- Insert an adopted buffer before the saved previous tab without selecting it.
local extra = vim.api.nvim_create_buf(false, true)
vim.api.nvim_open_term(extra, {})
local order = state.get_term_order()
local adopted = table.remove(order)
table.insert(order, 1, adopted)
state.set_term_order(order)
assert(current_id() == b and previous_id() == a, "insertion does not shift history")
state.remove_term_from_order(extra)
vim.api.nvim_buf_delete(extra, { force = true })
settle()
last()
assert(current_id() == a, "removal does not shift history")

terminal.vsplit()
settle()
-- Break the original pane (the one that existed when entry A was created).
vim.api.nvim_set_current_win(vim.t.term_winids[1])
terminal.break_pane_to_tab()
settle()
local broken = current_id()
assert(broken ~= a and previous_id() == a, "pane break assigns a fresh entry identity")
last()
assert(current_id() == a, "history survives breaking out the original buffer")

local source = vim.api.nvim_get_current_tabpage()
vim.cmd("tabnew")
settle()
terminal.toggle()
settle()
local target_previous = current_id()
local target = vim.api.nvim_get_current_tabpage()
vim.api.nvim_set_current_tabpage(source)
settle()
local transferred = current_id()
terminal.move_to_vim_tab(1)
settle()
assert(vim.api.nvim_get_current_tabpage() == target and current_id() == transferred,
	"Vim-tab transfer retains entry identity")
assert(previous_id() == target_previous, "transfer remembers the destination's selected terminal")
last()
assert(current_id() == target_previous, "last-tab returns to the destination terminal")

-- Persisted v4 entries without IDs get stable IDs once, not on every read.
local raw = vim.t.term_order
for _, entry in ipairs(raw) do entry.id = nil end
vim.t.term_order = raw
vim.t.term_prev_tab_idx = 2
local migrated = state.get_term_order()
local again = state.get_term_order()
assert(migrated[1].id == again[1].id and migrated[2].id == again[2].id,
	"legacy identities are persisted")
assert(vim.t.term_prev_tab_idx == nil and previous_id() == migrated[2].id,
	"positional history migrates to identity")
print("Tab history regressions passed")
