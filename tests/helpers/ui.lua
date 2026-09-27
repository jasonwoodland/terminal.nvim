-- Embedded Neovim with an attached UI and its own input/event loop. Consume UI
-- notifications directly: Neovim's built-in RPC client is not a UI client.
local M = {}
function M.start(root, width, height)
	local uv = vim.uv
	local input, output, errors = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
	local exited, stderr, replies, sequence = false, {}, {}, 0
	local process = assert(uv.spawn(vim.v.progpath, {
		args = { "--clean", "--embed" }, stdio = { input, output, errors },
	}, function() exited = true end))
	local decode_handle = function(_, data) return vim.mpack.decode(data) end
	local unpack = vim.mpack.Unpacker({ ext = { [0] = decode_handle, [1] = decode_handle, [2] = decode_handle } })
	local ui = { redraws = 0 }
	output:read_start(function(err, data)
		assert(not err, err)
		if not data then return end
		local pos, message = 1
		while pos <= #data do
			message, pos = unpack(data, pos)
			if message then
				if message[1] == 1 then replies[message[2]] = message end
				if message[1] == 2 and message[2] == "redraw" then ui.redraws = ui.redraws + 1 end
			end
		end
	end)
	errors:read_start(function(_, data) if data then stderr[#stderr + 1] = data end end)
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
		if not exited then
			input:write(vim.mpack.encode({ 2, "nvim_command", { "qa!" } }))
			if not vim.wait(1000, function() return exited end, 10) then process:kill("sigkill") end
		end
		for _, handle in ipairs({ input, output, errors, process }) do
			if not handle:is_closing() then handle:close() end
		end
	end
	local ok, err = pcall(function()
		ui.request("nvim_ui_attach", width or 100, height or 36, { rgb = true, ext_linegrid = true })
		ui.lua("vim.opt.runtimepath:prepend(...); vim.env.SHELL = '/bin/sh'; vim.o.swapfile = false", root)
	end)
	if not ok then ui.close(); error(err) end
	return ui
end
return M
