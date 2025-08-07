local M = {}
function M.check()
    vim.health.start("External Tools:")
    if vim.fn.executable("git") == 1 then
        vim.health.ok("{git} available")
    else
        vim.health.error("{git} not found")
    end
end
return M
