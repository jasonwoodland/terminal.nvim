-- terminal.nvim: digraph insertion for terminal mode (i_CTRL-K equivalent)

local M = {}
local ns = vim.api.nvim_create_namespace("terminal_digraph")
local active = nil
local watching_lifetime = false

local function close(session)
	if not session then return end
	session.done = true
	if active == session then
		vim.on_key(nil, ns)
		active = nil
	end
	if session.win and vim.api.nvim_win_is_valid(session.win) then
		pcall(vim.api.nvim_win_close, session.win, true)
	end
	if vim.api.nvim_buf_is_valid(session.buf) then
		pcall(vim.api.nvim_buf_delete, session.buf, { force = true })
	end
end

-- Modified keys may arrive as raw CSI-u / modifyOtherKeys terminal bytes.
local function key_to_str(key, typed)
	typed = typed or ""
	local cp, mod = typed:match("^\x1b%[(%d+);(%d+)u$")
	if not cp then mod, cp = typed:match("^\x1b%[27;(%d+);(%d+)~$") end
	if cp then
		mod = tonumber(mod) - 1
		local prefix = ""
		if mod % 2 ~= 0 then prefix = prefix .. "S-" end
		if math.floor(mod / 2) % 2 ~= 0 then prefix = prefix .. "A-" end
		if math.floor(mod / 4) % 2 ~= 0 then prefix = prefix .. "C-" end
		local base = vim.fn.keytrans(vim.fn.nr2char(tonumber(cp)))
		return "<" .. prefix .. (base:match("^<(.+)>$") or base) .. ">"
	end
	return vim.fn.keytrans(key)
end

local function start_session(job)
	close(active)
	local session = {
		buf = vim.api.nvim_create_buf(false, true),
		owner = vim.api.nvim_get_current_buf(),
		job = job,
	}
	active = session
	vim.bo[session.buf].bufhidden = "wipe"
	local width = math.min(11, vim.o.columns)
	local ok, win = pcall(vim.api.nvim_open_win, session.buf, false, {
		relative = "editor",
		width = width,
		height = 1,
		row = math.max(vim.o.lines - vim.o.cmdheight - 1, 0),
		col = vim.o.columns - width,
		style = "minimal",
		noautocmd = true,
		zindex = 200,
		focusable = false,
	})
	if not ok then
		close(session)
		error(win, 0)
	end
	session.win = win

	local function show(text)
		if vim.api.nvim_buf_is_valid(session.buf) then
			vim.api.nvim_buf_set_lines(session.buf, 0, -1, false, { text })
		end
	end
	show("^K")

	local function finish(text)
		-- Stop consuming keys now, not when the scheduled send runs. A
		-- previous session must never close or send into its replacement.
		session.done = true
		vim.on_key(nil, ns)
		vim.schedule(function()
			local send = active == session and text ~= nil
				and vim.api.nvim_get_current_buf() == session.owner
				and vim.api.nvim_buf_is_valid(session.owner)
				and vim.b[session.owner].terminal_job_id == session.job
				and vim.fn.mode() == "t"
			close(session)
			if send then pcall(vim.api.nvim_chan_send, session.job, text) end
		end)
	end

	local first = nil
	vim.on_key(function(key, typed)
		if session.done then return end
		if vim.fn.mode() ~= "t" or vim.api.nvim_get_current_buf() ~= session.owner then
			finish()
			return
		end
		if key == "" then return end
		if key == "\27" then
			finish()
		elseif key:byte(1) == 0x80 then
			finish(key_to_str(key, typed))
		elseif not first then
			first = key
			show("^K" .. vim.fn.keytrans(key))
		else
			-- The Vimscript API accepts exactly two bytes. Non-ASCII pairs
			-- have no digraph entry and use the second character directly.
			local result = key
			if #first == 1 and #key == 1 then result = vim.fn.digraph_get(first .. key) end
			finish(result)
		end
		return ""
	end, ns)
end

function M.setup(key)
	if not key then return end
	if type(key) == "table" then
		for _, item in ipairs(key) do M.setup(item) end
		return
	end
	if not watching_lifetime then
		watching_lifetime = true
		local group = vim.api.nvim_create_augroup("TerminalDigraph", { clear = true })
		local function cancel()
			local session = active
			if not session then return end
			session.done = true
			vim.on_key(nil, ns)
			vim.schedule(function() close(session) end)
		end
		vim.api.nvim_create_autocmd({ "BufLeave", "TermClose" }, {
			group = group,
			callback = function(ev)
				if active and ev.buf == active.owner then cancel() end
			end,
		})
		vim.api.nvim_create_autocmd("ModeChanged", { group = group, pattern = "t:*", callback = cancel })
	end
	vim.keymap.set("t", key, function()
		local job = vim.b.terminal_job_id
		if job then start_session(job) end
	end, { noremap = true, silent = true })
end

return M
