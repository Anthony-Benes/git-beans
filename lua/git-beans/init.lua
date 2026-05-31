local M = {}

---@class GitBeansCommand
---@field impl fun(args:string[], opts: table)
---@field complete? fun(arg_lead: string): string[] (optional)

---@type table<string, GitBeansCommand>
M.command = {
    status = require("git-beans.commands.status"),
    log = require("git-beans.commands.log"),
}

return M
