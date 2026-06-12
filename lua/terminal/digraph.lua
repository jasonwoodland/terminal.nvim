-- terminal.nvim: digraph insertion for terminal mode (i_CTRL-K equivalent)

local M = {}

local ns = vim.api.nvim_create_namespace("terminal_digraph")
local indicator_win = nil

local function close()
	vim.on_key(nil, ns)
	if indicator_win and vim.api.nvim_win_is_valid(indicator_win) then
		vim.api.nvim_win_close(indicator_win, true)
	end
	indicator_win = nil
end

local function start_session(job)
	-- Cancel any in-progress digraph session
	close()

	local buf = vim.api.nvim_create_buf(false, true)
	-- Place at the right edge of the statusline row (floating windows
	-- cannot render in the cmdline row; this is the closest valid row)
	local row = math.max(vim.o.lines - vim.o.cmdheight, 0)
	local width = 11
	indicator_win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = width,
		height = 1,
		row = row,
		col = vim.o.columns - width,
		style = "minimal",
		noautocmd = true,
		zindex = 200,
		focusable = false,
	})
	vim.bo[buf].modifiable = true

	local function show(text)
		if not (indicator_win and vim.api.nvim_win_is_valid(indicator_win)) then
			return
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
	end

	show("^K")

	-- Per :h i_CTRL-K, when {char1} is a special key it's inserted in <>
	-- form (e.g. <C-K><S-Space> inserts the literal text "<S-Space>").
	-- keytrans() mangles raw termcap bytes that arrive in terminal mode,
	-- so parse the underlying CSI-u / modifyOtherKeys sequence instead.
	local function key_to_str(key, typed)
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

	local c1 = nil
	vim.on_key(function(key, typed)
		-- Abort if user has left terminal mode
		if vim.fn.mode() ~= "t" then
			vim.schedule(close)
			return
		end

		if c1 == nil then
			if key == "\27" then
				vim.schedule(close)
				return ""
			end
			if key:byte(1) == 0x80 then
				local key_str = key_to_str(key, typed)
				vim.schedule(function()
					close()
					vim.api.nvim_chan_send(job, key_str)
				end)
				return ""
			end
			c1 = key
			show("^K" .. vim.fn.keytrans(key))
			return ""
		else
			local k2 = key
			vim.schedule(function()
				close()
				if k2 ~= "\27" then
					local dg = vim.fn.digraph_get(c1 .. k2)
					if dg ~= "" then
						vim.api.nvim_chan_send(job, dg)
					else
						-- No digraph found: re-inject so terminal mappings can fire
						vim.fn.feedkeys(c1 .. k2, "t")
					end
				end
			end)
			return ""
		end
	end, ns)
end

function M.setup(key)
	if not key or key == false then
		return
	end

	vim.keymap.set("t", key, function()
		local job = vim.b.terminal_job_id
		if not job then
			return
		end
		start_session(job)
	end, { noremap = true, silent = true })
end

return M
