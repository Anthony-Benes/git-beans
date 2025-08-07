local cmds = {
    git = "git",
    gitlog = "git log --oneline --graph --abbrev-commit --decorate --date=relative --all",
}

local M = {}

---@class GitBeansCommand
---@field impl fun(args:string[], opts: table)
---@field complete? fun(arg_lead: string): string[] (optional)

---@type table<string, GitBeansCommand>
M.command = {
    Hello = {
        impl = function(args, opts)
            print("Hello World")
        end,
    },
    Log = {
        impl = function(args, opts)
            M.open_hello_window()
        end,
    },
}

local function GitLog()
    local result = vim.fn.systemlist(cmds.gitlog)
    if vim.v.shell_error ~= 0 then
        result = { "Error running git log.", unpack(result) }
    elseif #result == 0 then
        result = { "No git history found." }
    end
    return result
end

function M.open_hello_window()
    local buf = vim.api.nvim_create_buf(false, true)
    local log = GitLog()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, log)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_set_option_value("filetype", "git", { buf = buf })
    local height = math.min(#log, 20)
    local width = 100
    local ui = vim.api.nvim_list_uis()[1]
    local row = math.floor((ui.height - height) / 2)
    local col = math.floor((ui.width - width) / 2)
    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = vim.g.git_beans.border_chars,
        title = " Git Log ",
        title_pos = "center",
    }
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    vim.keymap.set("n", 'q', function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end
print("Loaded GitBeans")
return M
