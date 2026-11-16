-- Usage: nvim --clean --headless -l tests/abbreviations.lua
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
for _, enabled in ipairs({ true, false }) do
	local ui = require("tests.helpers.ui").start(root)
	local ok, err = pcall(function()
		ui.lua([[
			vim.cmd("cnoreabbrev <expr> st (getcmdtype() == ':' && getcmdline() == 'st') ? 'stop' : 'st'")
			require('terminal').setup({ keys = false, cabbrev = ... })
		]], enabled)
		ui.input(":st ")
		ui.wait("return vim.fn.getcmdline() == " .. string.format("%q", enabled and "TermSplit " or "stop "),
			"abbreviation setting controls interactive expansion")
		ui.input("<Esc>")
		ui.input(":tsplit ")
		ui.wait("return vim.fn.getcmdline() == " .. string.format("%q", enabled and "TermSplit " or "tsplit "),
			"disabled aliases are not installed")
		ui.input("<Esc>")
		ui.input(":tpicker ")
		ui.wait("return vim.fn.getcmdline() == " .. string.format("%q", enabled and "TermPicker " or "tpicker "),
			"picker abbreviation respects cabbrev")
		ui.input("<Esc>")
		ui.input(":echo st ")
		ui.wait("return vim.fn.getcmdline() == 'echo st '", "arguments do not expand")
		ui.input("<Esc>")
		ui.input("/st ")
		ui.wait("return vim.fn.getcmdline() == 'st '", "search patterns do not expand")
		ui.input("<Esc>")
		assert(ui.lua("return vim.fn.exists(':TermSplit') == 2"), "full commands remain available")
	end)
	ui.close()
	assert(ok, err)
end
print("Command abbreviation regressions passed")
