-- Usage: nvim --clean --headless -l benchmarks/ui.lua > /tmp/terminal-benchmark.json
-- Measures synchronous operations, including redraw generation to an attached
-- RPC UI. It does not measure host terminal rendering or interactive latency.
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
local ui = dofile(root .. "/tests/helpers/ui.lua").start(root, 160, 50)
local ok, result = xpcall(function()
	return ui.lua([[
		local terminal = require('terminal')
		local window = require('terminal.window')
		local state = require('terminal.state')
		local layout = require('terminal.float_layout')
		local frame = require('terminal.frame')
		terminal.setup({ keys = false, set_buffer_name = false, float = {
			enabled = true, padding = { x = 3, y = 2 }, border = 'rounded', overlay = false,
		} })
		terminal.toggle()
		for _ = 1, 3 do terminal.vsplit() end
		terminal.new()
		for _ = 1, 3 do terminal.vsplit() end
		window.save_tab_state()
		local entries = state.get_tabs()
		assert(frame.same_geometry(entries[1].layout, entries[2].layout), 'benchmark requires matching tab geometries')
		local results = {}
		local function measure(name, iterations, run)
			for i = 1, 10 do run(i); vim.cmd('redraw') end
			collectgarbage('collect')
			local samples = {}
			for i = 1, iterations do
				local start = vim.uv.hrtime()
				run(i)
				vim.cmd('redraw')
				samples[i] = (vim.uv.hrtime() - start) / 1e6
			end
			table.sort(samples)
			results[#results + 1] = { operation = name, iterations = iterations,
				median_ms = samples[math.ceil(iterations / 2)], p95_ms = samples[math.ceil(iterations * .95)] }
		end
		local entry, base = state.get_current_tab(), window.get_float_win_config()
		local canvas = vim.api.nvim_win_get_buf(vim.t.term_canvas_winid)
		local tick = vim.api.nvim_buf_get_changedtick(canvas)
		measure('unchanged canvas', 100, function() layout.update_canvas(entry.layout, base) end)
		results[#results].buffer_changes = vim.api.nvim_buf_get_changedtick(canvas) - tick
		measure('matching geometry tab switch', 60, function(i) terminal.go_to(i % 2 + 1) end)
		measure('four-pane rebuild', 40, function() window.rebuild_tab() end)
		entry = state.get_current_tab()
		local _, separators = frame.rects(entry.layout)
		measure('changing pane geometry', 60, function(i)
			frame.drag(entry.layout, separators[1], i % 2 == 1 and 1 or -1)
			layout.apply_layout(entry)
		end)
		return { version = vim.version(), system = vim.uv.os_uname(), width = 160, height = 50, panes = 4, results = results }
	]])
end, debug.traceback)
ui.close()
assert(ok, result)
io.write(vim.json.encode(result), '\n')
