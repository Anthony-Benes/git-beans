if vim.g.git_beans == nil then
    vim.g.git_beans = {}
end

if vim.g.git_beans.is_loaded then return end

-- Set Default Values. These can be overwritten for customization.
if not vim.g.git_beans.border_chars then
    vim.g.git_beans.border_chars = {'╭','─', '╮', '│', '╯','─', '╰', '│'}
end

vim.api.nvim_create_user_command("GitBeans",
    ---@param opts table :h lua-guide-commands-create
    function(opts)
        local fargs = opts.fargs
        local sub_key = fargs[1]
        local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
        local gitBeans = require("git-beans")
        local sub_cmd = gitBeans.command[sub_key]
        if not sub_cmd then
            vim.notify("GitBeans: Unknown command: " .. sub_key, vim.log.levels.ERROR)
            return
        end
        sub_cmd.impl(args, opts)
    end, {
    nargs = "+",
    desc = "Git commands and visuals",
    complete = function(arg_lead, cmdline, _)
        local sub_key, sub_arg_lead = cmdline:match("^['<,'>]*GitBeans[!]*%s(%S+)%s(.*)$")
        local command_tbl = require("git-beans").command
        if sub_key and sub_arg_lead and command_tbl[sub_key] and command_tbl[sub_key].complete then
            return command_tbl[sub_key].complete(sub_arg_lead)
        end
        if cmdline:match("^['<,'>]*GitBeans[!]*%s+%w*$") then
            local sub_keys = vim.tbl_keys(command_tbl)
            return vim.iter(sub_keys):filter(function(key)
                return key:find(arg_lead) ~= nil
            end):totable()
        end
    end,
    bang = true,
})

vim.g.git_beans.is_loaded = true
