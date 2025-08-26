local M = {}

---@class GitBeansCommand
---@field impl fun(args:string[], opts: table)
---@field complete? fun(arg_lead: string): string[] (optional)

---@type table<string, GitBeansCommand>
M.command = {
    Status = {
        impl = function(args, opts)
            require("git-beans.ui.status").open_git_status()
        end,
    },
    Log = {
        impl = function(args, opts)
            require("git-beans.ui.log").open_git_log()
        end,
    },
}

return M
