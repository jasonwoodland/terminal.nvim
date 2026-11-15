-- Usage: nvim --clean --headless -l tests/native_session.lua
if vim.fn.exists("##SessionWritePre") == 0 then print("SKIP native sessions: SessionWritePre unavailable"); return end
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
for _, phase in ipairs({ "write", "read", "current" }) do
	local output, status = {}, nil
	local job = vim.fn.jobstart({ vim.v.progpath, "--clean", "--headless", "-l", root .. "/tests/fixtures/native_session.lua" }, {
		env = { TERMINAL_SESSION_ROOT = root, TERMINAL_SESSION_FILE = directory .. "/Session.vim",
			TERMINAL_SESSION_CWD = directory, TERMINAL_SESSION_PHASE = phase },
		on_stdout = function(_, lines) vim.list_extend(output, lines) end,
		on_stderr = function(_, lines) vim.list_extend(output, lines) end,
		on_exit = function(_, code) status = code end,
	})
	assert(job > 0)
	if not vim.wait(15000, function() return status ~= nil end, 10) then
		vim.fn.jobstop(job); error("native session child timed out")
	end
	assert(status == 0, phase .. ": " .. table.concat(output, "\n"))
end
vim.fn.delete(directory, "rf")
print("Native session integration passed")
