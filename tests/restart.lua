-- Usage: nvim --clean --headless -l tests/restart.lua (requires python3 and a Unix PTY)
if vim.fn.exists("##SessionWritePre") == 0 or vim.fn.exists(":restart") == 0 or vim.fn.has("win32") == 1 then
	print("SKIP native restart: session hooks or Unix PTY unavailable")
	return
end
local root = vim.fn.fnamemodify(arg[0], ":p:h:h")
local output, status = {}, nil
local job = vim.fn.jobstart({ "python3", root .. "/tests/fixtures/restart.py", vim.v.progpath, root }, {
	on_stdout = function(_, lines) vim.list_extend(output, lines) end,
	on_stderr = function(_, lines) vim.list_extend(output, lines) end,
	on_exit = function(_, code) status = code end,
})
assert(job > 0)
if not vim.wait(35000, function() return status ~= nil end, 10) then
	vim.fn.jobstop(job); error("restart test timed out")
end
assert(status == 0, table.concat(output, "\n"))
print("Native restart integration passed")
