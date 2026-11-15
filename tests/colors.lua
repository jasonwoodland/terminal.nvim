-- Usage: nvim --clean --headless -l tests/colors.lua (requires python3)
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
local config = require("terminal.config")
local colors = require("terminal.colors")
vim.api.nvim_create_augroup("Term", {})
vim.o.termguicolors = true
vim.o.background = "dark"
vim.api.nvim_set_hl(0, "Normal", { fg = "#ebdbb2", bg = "#282828" })

local function query(fg, bg, terminator, preserve_terminator, managed)
	local path = vim.fn.tempname()
	vim.cmd("enew")
	if managed ~= false then
		vim.b.terminal_managed = true
		vim.b.term_owner_tab = vim.api.nvim_get_current_tabpage()
	end
	local job = vim.fn.termopen({ "python3", root .. "/tests/fixtures/color_query.py", path, terminator or "st" })
	assert(vim.wait(3000, function() return vim.fn.jobwait({ job }, 0)[1] ~= -1 end, 10), "query completes")
	local file = assert(io.open(path, "rb"), "query capture exists")
	local result = file:read("*a")
	file:close()
	vim.fn.delete(path)
	vim.api.nvim_buf_delete(0, { force = true })
	local normalized = result:gsub("\27\\", "\7")
	local expected = "\27]10;rgb:" .. fg .. "\7\27]11;rgb:" .. bg .. "\7"
	assert(normalized == expected, "exactly one correct reply per query: " .. vim.inspect(result))
	if preserve_terminator then
		local ending = terminator == "bel" and "\7" or "\27\\"
		assert(result == expected:gsub("\7", ending), "reply preserves request terminator")
	end
end

config.setup({ osc_colors = false })
colors.setup()
query("ffff/ffff/ffff", "0000/0000/0000")

local unrelated = 0
vim.api.nvim_create_autocmd("TermRequest", {
	group = "Term",
	callback = function() unrelated = unrelated + 1 end,
})
config.setup({})
colors.setup()
colors.setup() -- Must not add duplicate responses.
query("ffff/ffff/ffff", "0000/0000/0000", "st", false, false)
query("ebeb/dbdb/b2b2", "2828/2828/2828", "bel", true)
query("ebeb/dbdb/b2b2", "2828/2828/2828", "st", true)
assert(unrelated >= 4, "other TermRequest handlers survive")

vim.o.background = "light"
vim.api.nvim_set_hl(0, "Normal", { fg = "#1d2021", bg = "#ffffff" })
query("1d1d/2020/2121", "ffff/ffff/ffff")
vim.api.nvim_set_hl(0, "Normal", { fg = "#000000", bg = "#ffffff", reverse = true })
query("ffff/ffff/ffff", "0000/0000/0000")

vim.o.background = "dark"
vim.api.nvim_set_hl(0, "Normal", { fg = "#ebdbb2" })
query("ebeb/dbdb/b2b2", "0000/0000/0000")
vim.api.nvim_set_hl(0, "Normal", { bg = "#282828" })
query("ffff/ffff/ffff", "2828/2828/2828")
vim.api.nvim_set_hl(0, "Normal", { fg = "#000000", bg = "#000000" })
query("0000/0000/0000", "0000/0000/0000")

vim.o.termguicolors = false
vim.api.nvim_set_hl(0, "Normal", { fg = "#ebdbb2", bg = "#282828" })
query("ffff/ffff/ffff", "0000/0000/0000")

-- Non-query requests and virtual terminals without a job must be harmless.
vim.api.nvim_exec_autocmds("TermRequest", { data = { sequence = "\27]11;#ffffff" } })
vim.api.nvim_exec_autocmds("TermRequest", { data = { sequence = "\27]11;?" } })
print("Terminal color query regressions passed")
