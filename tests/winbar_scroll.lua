local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
vim.opt.runtimepath:prepend(root)
local ui = require("tests.helpers.ui").start(root, 60, 30)
local ok, err = pcall(function()
	ui.lua([=[
		local terminal = require('terminal')
		local winbar = require('terminal.winbar')
		terminal.setup({keys=false})
		local buffers = {}
		for i = 1, 7 do buffers[i] = terminal.new({name='终端 ' .. i .. ' title'}) end
		local function check(index)
			assert(terminal.focus(buffers[index]) ~= false)
			winbar.update()
			local win = vim.t.term_winbar_winid
			local left = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
			local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win),0,1,false)[1]
			local range = winbar.get_click_ranges()[index]
			local first = vim.fn.strdisplaywidth(line:sub(1,range.start_col))
			local last = vim.fn.strdisplaywidth(line:sub(1,range.end_col))
			local width = vim.api.nvim_win_get_width(win)
			assert((last - first > width and first == left)
				or (first >= left and last <= left + width),
				'active title is visible: ' .. vim.inspect({index, first, last, left}))
			assert(vim.api.nvim_get_current_buf() == buffers[index], 'scroll preserves terminal focus')
			return left
		end
		assert(check(7) > 0, 'last tab scrolls right')
		local previous = check(7)
		assert(check(7) == previous, 'refresh preserves the viewport')
		check(4)
		assert(check(1) == 0, 'first tab scrolls back to the start')
		terminal.float_toggle()
		assert(check(7) > 0, 'floating winbar scrolls too')
		assert(check(1) == 0, 'floating winbar returns to the start')
		terminal.float_toggle()
		vim.b[buffers[7]].terminal_custom_name = string.rep('界',80)
		assert(terminal.focus(buffers[7]) ~= false)
		winbar.update()
		local win = vim.t.term_winbar_winid
		local left = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol
		local range = winbar.get_click_ranges()[7]
		local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win),0,1,false)[1]
		assert(left == vim.fn.strdisplaywidth(line:sub(1,range.start_col)), 'oversized title shows its beginning')
	]=])
end)
ui.close()
assert(ok, err)
print("Winbar overflow scrolling passed")
