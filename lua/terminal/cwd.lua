local M = {}

local function usable(path)
	return type(path) == "string" and path:sub(1, 1) == "/"
		and not path:find("\0", 1, true) and vim.fn.isdirectory(path) == 1
end

-- Read the shell process directly so ordinary `cd` works without shell
-- integration. Do not inspect children: a running command may use another cwd.
local function process_cwd(buf)
	local job = vim.b[buf].terminal_job_id
	if not job then return end
	local ok, pid = pcall(vim.fn.jobpid, job)
	if not ok or pid <= 0 then return end
	local path = vim.uv.fs_readlink("/proc/" .. pid .. "/cwd")
	if usable(path) then return path end
	if vim.fn.has("macunix") == 1 and vim.fn.executable("lsof") == 1 then
		local success, result = pcall(function()
			return vim.system({ "lsof", "-a", "-p", tostring(pid), "-d", "cwd", "-Fn" },
				{ text = true }):wait(1000)
		end)
		if success and result.code == 0 then
			for line in (result.stdout or ""):gmatch("[^\n]+") do
				if line:sub(1, 1) == "n" and usable(line:sub(2)) then return line:sub(2) end
			end
		end
	end
end

function M.resolve(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if require("terminal.state").is_managed(buf) then
		local actual = process_cwd(buf)
		if actual then return actual end
		local current = vim.b[buf].terminal_cwd
		if usable(current) then return current end
		local launch = vim.b[buf].terminal_launch
		if launch and usable(launch.cwd) then return launch.cwd end
	end
	return vim.fn.getcwd()
end

function M.setup()
	vim.api.nvim_create_autocmd("TermRequest", {
		group = "Term",
		callback = function(ev)
			if not require("terminal.state").is_managed(ev.buf) then return end
			local host, path = ev.data.sequence:match("^\27%]7;file://([^/]*)(/.*)$")
			if not path then return end
			-- A remote shell's directory must never be treated as a local path.
			if host ~= "" and host ~= "localhost" and host ~= vim.uv.os_gethostname() then return end
			path = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
			if usable(path) then vim.b[ev.buf].terminal_cwd = path end
		end,
	})
end

return M
