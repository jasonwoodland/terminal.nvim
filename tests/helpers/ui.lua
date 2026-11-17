-- Embedded Neovim with an attached UI and its own input/event loop. Consume UI
-- notifications directly: Neovim's built-in RPC client is not a UI client.
local M = {}
function M.start(root, width, height)
	local uv = vim.uv
	local input, output, errors = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
	local exited, stderr, replies, sequence = false, {}, {}, 0
	local exit_code, exit_signal, closed
	local shutting_down, output_done, stderr_done = false, false, false
	local child_errors = {}
	local process = assert(uv.spawn(vim.v.progpath, {
		args = { "--clean", "--embed" }, stdio = { input, output, errors },
	}, function(code, signal)
		exited, exit_code, exit_signal = true, code, signal
		if not shutting_down then child_errors[#child_errors + 1] = "UI child exited before teardown" end
	end))
	local decode_handle = function(_, data) return vim.mpack.decode(data) end
	local unpack = vim.mpack.Unpacker({ ext = { [0] = decode_handle, [1] = decode_handle, [2] = decode_handle } })
	local ui = { redraws = 0 }
	local rows = {}
	function ui.find_text(value)
		for row, cells in pairs(rows) do
			local filled = {}
			for col = 1, math.max(width or 100, #cells) do filled[col] = cells[col] or " " end
			local line = table.concat(filled)
			local col = line:find(value, 1, true)
			if col then return { row, col - 1 } end
		end
	end
	output:read_start(function(err, data)
		assert(not err, err)
		if not data then output_done = true; return end
		local pos, message = 1
		while pos <= #data do
			message, pos = unpack(data, pos)
			if message then
				if message[1] == 1 then replies[message[2]] = message end
				if message[1] == 2 and message[2] == "redraw" then
					ui.redraws = ui.redraws + 1
					for _, event in ipairs(message[3]) do
						if event[1] == "msg_show" then
							for i = 2, #event do
								local kind, chunks = event[i][1], event[i][2]
								if kind == "emsg" or kind == "lua_error" or kind == "rpc_error" or kind == "echoerr" then
									local parts = {}
									for _, chunk in ipairs(chunks) do parts[#parts + 1] = chunk[2] end
									child_errors[#child_errors + 1] = table.concat(parts)
								end
							end
						end
						if event[1] == "grid_clear" or event[1] == "grid_resize" then rows = {} end
						if event[1] == "grid_line" then
							for i = 2, #event do
								local line = event[i]
								local row, col = line[2], line[3] + 1
								rows[row] = rows[row] or {}
								for _, cell in ipairs(line[4]) do
									for _ = 1, cell[3] or 1 do rows[row][col] = cell[1]; col = col + 1 end
								end
							end
						end
					end
				end
			end
		end
	end)
	errors:read_start(function(_, data)
		if data then stderr[#stderr + 1] = data else stderr_done = true end
	end)
	function ui.request(method, ...)
		sequence = sequence + 1
		local id = sequence
		input:write(vim.mpack.encode({ 0, id, method, { ... } }))
		assert(vim.wait(3000, function() return replies[id] ~= nil or exited end, 5), "RPC timed out: " .. method)
		local reply = replies[id]
		replies[id] = nil
		assert(reply, "child exited: " .. table.concat(stderr))
		assert(reply[3] == vim.NIL, vim.inspect(reply[3]))
		return reply[4]
	end
	function ui.lua(code, ...) return ui.request("nvim_exec_lua", code, { ... }) end
	function ui.input(keys) return ui.request("nvim_input", keys) end
	function ui.wait(code, message)
		local last
		local ok = vim.wait(3000, function()
			last = ui.lua(code)
			return last == true
		end, 10)
		assert(ok, message .. ": " .. vim.inspect(last))
	end
	function ui.close()
		if closed then return end
		closed = true
		if not exited then
			local ok, message = pcall(ui.lua, "return vim.v.errmsg")
			if not ok or message ~= "" then child_errors[#child_errors + 1] = tostring(message) end
			shutting_down = true
			input:write(vim.mpack.encode({ 2, "nvim_command", { "qa!" } }))
			if not vim.wait(1000, function() return exited end, 10) then
				child_errors[#child_errors + 1] = "UI child did not shut down"
				process:kill("sigkill")
				vim.wait(1000, function() return exited end, 10)
			end
		end
		if not vim.wait(500, function() return output_done and stderr_done end, 10) then
			child_errors[#child_errors + 1] = "UI child streams did not close"
		end
		for _, handle in ipairs({ input, output, errors, process }) do
			if not handle:is_closing() then handle:close() end
		end
		if exit_code ~= 0 or exit_signal ~= 0 then
			child_errors[#child_errors + 1] = ("UI child exited with code %s, signal %s"):format(tostring(exit_code), tostring(exit_signal))
		end
		if #stderr > 0 then child_errors[#child_errors + 1] = table.concat(stderr) end
		assert(#child_errors == 0, table.concat(child_errors, "\n"))
	end
	local ok, err = pcall(function()
		ui.request("nvim_ui_attach", width or 100, height or 36, { rgb = true, ext_linegrid = true, ext_messages = true })
		ui.lua("vim.opt.runtimepath:prepend(...); vim.env.SHELL = '/bin/sh'; vim.o.swapfile = false", root)
	end)
	if not ok then ui.close(); error(err) end
	return ui
end
return M
