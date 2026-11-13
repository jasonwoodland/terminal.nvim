-- Usage: nvim --clean --headless -l tests/mouse_input.lua (requires python3)
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
local function bytes(path)
	local file = io.open(path, "rb")
	if not file then return "" end
	local value = file:read("*a")
	file:close()
	return value
end
for _, floating in ipairs({ false, true }) do
	local ui = dofile(root .. "/tests/helpers/ui.lua").start(root)
	local capture = vim.fn.tempname()
	local ok, err = xpcall(function()
		ui.lua([[
			local root, capture, floating = ...
			require('terminal').setup({ set_buffer_name = false, float = { enabled = floating } })
			vim.o.mouse = 'a'
			_G.mouse_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_call(mouse_buf, function()
				vim.fn.termopen({ 'python3', root .. '/tests/fixtures/terminal_reader.py', capture, 'mouse' })
			end)
			require('terminal').toggle()
		]], root, capture, floating)
		ui.wait([[return vim.api.nvim_get_current_buf() == mouse_buf and vim.api.nvim_get_mode().mode == 't'
			and table.concat(vim.api.nvim_buf_get_lines(mouse_buf, 0, -1, false), '\n'):find('READER_READY') ~= nil]], 'mouse application ready')
		local pos = ui.lua([[local p = vim.api.nvim_win_get_position(0); return {p[1] + 2, p[2] + 3}]])
		local expected = ''
		for _, event in ipairs({
			{ 'left', 'press', 0, 'M' }, { 'left', 'drag', 32, 'M', 1 }, { 'left', 'release', 0, 'm', 1 },
			{ 'right', 'press', 2, 'M' }, { 'right', 'release', 2, 'm' },
			{ 'wheel', 'up', 64, 'M' }, { 'wheel', 'down', 65, 'M' },
		}) do
			local offset = event[5] or 0
			ui.request('nvim_input_mouse', event[1], event[2], '', 0, pos[1], pos[2] + offset)
			expected = expected .. string.format('\27[<%d;%d;3%s', event[3], 4 + offset, event[4])
			assert(vim.wait(3000, function() return bytes(capture) == expected end, 10),
				event[1] .. ' ' .. event[2] .. ' reaches application: ' .. vim.inspect(bytes(capture)))
		end
		assert(ui.lua([[return vim.api.nvim_get_mode().mode == 't' and vim.v.errmsg == '']]), 'mouse input preserves Terminal mode')
	end, debug.traceback)
	ui.close()
	vim.fn.delete(capture)
	assert(ok, err)
end
print('Terminal application mouse input regressions passed')
