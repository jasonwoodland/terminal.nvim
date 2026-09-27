local M = {}

function M.key_list(value)
  if value == false or value == nil then return {} end
  return type(value) == "table" and value or { value }
end

function M.alias(lhs, rhs)
  vim.cmd(
    string.format(
      'cnoreabbrev <expr> %s (getcmdtype() == ":" && getcmdline() =~ "^%s$") ? "%s" : "%s"',
      lhs,
      lhs,
      rhs,
      lhs
    )
  )
end

return M
