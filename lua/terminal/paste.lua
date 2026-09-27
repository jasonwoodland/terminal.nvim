-- Use Neovim's terminal paste path so libvterm supplies bracketed-paste markers
-- only when the child requests them (and honors terminalpastefilter, if present).
local M = {}

local function target()
	local buf = vim.api.nvim_get_current_buf()
	return { buf = buf, job = vim.b[buf].terminal_job_id }
end

local function paste(owner, text)
	if not owner.job or not vim.api.nvim_buf_is_valid(owner.buf)
		or vim.api.nvim_get_current_buf() ~= owner.buf
		or vim.b[owner.buf].terminal_job_id ~= owner.job then return end
	local mode = vim.api.nvim_get_mode().mode
	if mode ~= "t" and mode ~= "nt" then return end
	return vim.api.nvim_paste(text, false, -1)
end

function M.register()
	local owner = target()
	local ok, reg = pcall(vim.fn.getcharstr)
	if not ok or reg == "\27" or reg == "\3" then return end
	local got, text = pcall(vim.fn.getreg, reg)
	if got then paste(owner, text) end
end

function M.expression()
	local owner = target()
	local entered, expr = pcall(vim.fn.input, "=")
	if not entered or expr == "" then return end
	local ok, result = pcall(vim.fn.eval, expr)
	if not ok then
		vim.notify("Invalid expression: " .. result, vim.log.levels.ERROR)
		return
	end
	paste(owner, tostring(result))
end

return M
